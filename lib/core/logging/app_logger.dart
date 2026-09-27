import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Severity of a log record. Four levels is the whole vocabulary: a larger set
/// costs filtering decisions at every call site and buys nothing.
enum LogLevel { debug, info, warn, error }

/// Destination for a batch of formatted lines.
///
/// Abstracting the sink keeps [AppLogger] free of Flutter bindings and of any
/// filesystem assumption, which is what makes the non-blocking and bounded
/// behaviour testable without a device.
typedef LogWriter = Future<void> Function(List<String> lines);

/// Non-blocking, bounded, dependency-free logger (Protocol 4).
///
/// Three properties the rest of the app relies on:
///
///  * **Non-blocking.** A log call formats a string and appends it to a queue,
///    then returns. Persistence is fired with `unawaited`, so no call site ever
///    waits on I/O.
///  * **Bounded.** The queue is capped at [capacity]; the oldest lines are
///    dropped past that. A device with no free space, or a crash loop, cannot
///    grow the heap without limit.
///  * **Infallible.** A failing sink increments a counter and drops the batch.
///    Logging never propagates an exception into product code.
///
/// Secrets are scrubbed on the way out: Supabase access tokens are JWTs and are
/// the one credential most likely to reach a log line by accident.
class AppLogger {
  AppLogger({
    LogWriter? writer,
    this.capacity = 500,
    this.batchSize = 32,
    this.flushInterval = const Duration(seconds: 5),
    this.minLevel = LogLevel.debug,
  }) : _writer = writer ?? _discard;

  /// Process-wide instance used by the application. Tests construct their own
  /// and call the same methods, so the two paths cannot diverge.
  static final AppLogger instance = AppLogger();

  void debug(String message, [Map<String, Object?> data = const {}]) =>
      log(LogLevel.debug, message, data);

  void info(String message, [Map<String, Object?> data = const {}]) =>
      log(LogLevel.info, message, data);

  void warn(String message, [Map<String, Object?> data = const {}]) =>
      log(LogLevel.warn, message, data);

  void error(
    String message, [
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> data = const {},
  ]) {
    log(LogLevel.error, message, <String, Object?>{
      ...data,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stack': stackTrace.toString(),
    });
  }

  /// Matches a three-segment base64url JWT.
  static final RegExp _jwtPattern = RegExp(
    r'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{4,}',
  );

  LogWriter _writer;
  final int capacity;
  final int batchSize;
  final Duration flushInterval;
  final LogLevel minLevel;

  final ListQueue<String> _buffer = ListQueue<String>();

  Timer? _timer;
  bool _flushing = false;
  int _written = 0;
  int _dropped = 0;
  int _failures = 0;

  /// Begins periodic draining. Safe to call more than once.
  void start() {
    _timer ??= Timer.periodic(flushInterval, (_) => unawaited(flush()));
  }

  /// Redirects output to [writer], discarding nothing: anything already queued
  /// still goes to the original sink on its next flush.
  ///
  /// Called once during bootstrap, because the file sink needs platform
  /// channels that are not available before `runApp`.
  void useWriter(LogWriter writer) => _writer = writer;

  /// Stops the timer and makes a final best-effort flush.
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await flush();
  }

  int get written => _written;
  int get dropped => _dropped;
  int get failures => _failures;
  int get buffered => _buffer.length;

  /// Records a line. Returns immediately; never throws.
  void log(
    LogLevel level,
    String message, [
    Map<String, Object?> data = const {},
  ]) {
    if (level.index < minLevel.index) return;

    _buffer.addLast(_format(level, message, data));

    while (_buffer.length > capacity) {
      _buffer.removeFirst();
      _dropped++;
    }

    if (_buffer.length >= batchSize) unawaited(flush());
  }

  /// Hands the queued lines to the sink. Concurrent calls collapse: a second
  /// call while a flush is in flight returns at once, and the periodic timer
  /// picks up whatever is still queued.
  Future<void> flush() async {
    if (_flushing || _buffer.isEmpty) return;
    _flushing = true;
    final batch = _buffer.toList(growable: false);
    _buffer.clear();
    try {
      await _writer(batch);
      _written += batch.length;
    } catch (_) {
      _failures++;
    } finally {
      _flushing = false;
    }
  }

  String _format(LogLevel level, String message, Map<String, Object?> data) {
    final StringBuffer line = StringBuffer()
      ..write(DateTime.now().toIso8601String())
      ..write(' ')
      ..write(level.name.toUpperCase().padRight(5))
      ..write(' ')
      ..write(message);
    if (data.isNotEmpty) line.write(' ${_encode(data)}');
    return redact(line.toString());
  }

  static String _encode(Map<String, Object?> data) {
    try {
      return jsonEncode(data);
    } catch (_) {
      // A value that cannot be encoded must not cost us the rest of the line.
      return '<unencodable data>';
    }
  }

  /// Replaces anything shaped like a JWT with a placeholder.
  static String redact(String line) =>
      line.replaceAll(_jwtPattern, '<redacted-jwt>');

  static Future<void> _discard(List<String> lines) async {}
}

/// Forwards each batch to two sinks, in order.
///
/// Exists because a file-only sink makes a debug build indistinguishable from a
/// silent one: `adb logcat` shows the framework's own chatter and none of the
/// app's errors, which reads exactly like there being no error to find. The
/// console half is what makes a logged failure visible while it is being
/// diagnosed.
///
/// The two halves are independent. A console that throws must not cost the
/// lines that are already on their way to disk, and a disk that is full must
/// not stop them reaching the console — which is the case this is built for.
class TeeLogWriter {
  TeeLogWriter(this.primary, this.secondary);

  final LogWriter primary;
  final LogWriter secondary;

  Future<void> call(List<String> lines) async {
    await _guard(primary, lines);
    await _guard(secondary, lines);
  }

  static Future<void> _guard(LogWriter writer, List<String> lines) async {
    try {
      await writer(lines);
    } catch (_) {
      // A failing half is not allowed to take the other one down with it.
    }
  }
}

/// Appends batches to a log file, rotating at [maxBytes].
///
/// Written against the [LogWriter] function type rather than implementing it as
/// an interface: a class with a `call` method is already assignable to
/// `Future<void> Function(List<String>)`.
///
/// Writes go through the OS without an explicit flush, which is what keeps
/// [AppLogger.flush] cheap. One archive generation is kept, so a crash loop
/// cannot fill the device.
class RollingFileLogWriter {
  RollingFileLogWriter(this.file, {this.maxBytes = 512 * 1024});

  final File file;
  final int maxBytes;

  /// Builds a writer rooted in the platform's application-support directory,
  /// which is private to the app and not visible to the user.
  static Future<RollingFileLogWriter> inAppSupportDirectory({
    String fileName = 'moaen.log',
  }) async {
    final Directory dir = await getApplicationSupportDirectory();
    return RollingFileLogWriter(File('${dir.path}${Platform.pathSeparator}$fileName'));
  }

  Future<void> call(List<String> lines) async {
    final File archive = File('${file.path}.1');

    if (await file.exists() && await file.length() > maxBytes) {
      if (await archive.exists()) await archive.delete();
      await file.rename(archive.path);
    } else {
      await file.parent.create(recursive: true);
    }

    await file.writeAsString(
      '${lines.join('\n')}\n',
      mode: FileMode.append,
      flush: false,
    );
  }
}
