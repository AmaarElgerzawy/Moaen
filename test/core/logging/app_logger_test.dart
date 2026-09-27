import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moaen/core/logging/app_logger.dart';

/// A sink that records everything it is handed.
LogWriter _recordingSink(List<String> into) =>
    (List<String> lines) async => into.addAll(lines);

void main() {
  late List<String> sink;
  late AppLogger logger;

  setUp(() {
    sink = <String>[];
    logger = AppLogger(
      writer: _recordingSink(sink),
      // Large batch so flushes are explicit, and a far-off interval so the
      // timer never fires during a test.
      capacity: 10,
      batchSize: 1000,
      flushInterval: const Duration(days: 1),
    );
  });

  test('hands queued lines to the sink on flush', () async {
    logger.info('first');
    logger.warn('second', <String, Object?>{'count': 2});

    expect(sink, isEmpty, reason: 'logging must not write synchronously');

    await logger.flush();

    expect(sink, hasLength(2));
    expect(sink.first, contains('INFO  first'));
    expect(sink.last, contains('WARN  second'));
    expect(sink.last, contains('"count":2'));
  });

  test('drops records below the minimum level', () async {
    final AppLogger quiet = AppLogger(
      writer: _recordingSink(sink),
      minLevel: LogLevel.warn,
      batchSize: 1000,
    )
      ..debug('chatty')
      ..info('routine');

    await quiet.flush();

    expect(sink, isEmpty);
    expect(quiet.dropped, 0, reason: 'filtered records are not counted as dropped');
  });

  test('never exceeds capacity and discards the oldest lines first', () async {
    for (int i = 0; i < 25; i++) {
      logger.info('line-$i');
    }

    expect(logger.buffered, 10, reason: 'the queue must stay bounded');
    expect(logger.dropped, 15);

    await logger.flush();
    expect(sink, hasLength(10));
    expect(sink.first, contains('line-15'), reason: 'oldest lines go first');
    expect(sink.last, contains('line-24'));
  });

  test('redacts JWT-shaped tokens', () async {
    logger.info(
      'token leak',
      <String, Object?>{
        'access_token':
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r',
      },
    );
    await logger.flush();

    expect(sink.single, contains('<redacted-jwt>'));
    expect(sink.single, isNot(contains('dBjftJeZ4CVPmB92K27uhbUJU1p1r')));
  });

  test('a failing sink is counted and never propagates to the caller', () async {
    final AppLogger fragile = AppLogger(
      writer: (List<String> lines) async => throw const FileSystemException('disk full'),
      batchSize: 1000,
    );

    fragile.error('boot failed');
    await expectLater(fragile.flush(), completes);
    expect(fragile.failures, 1);
    expect(fragile.written, 0);
  });

  test('unencodable data does not cost us the line', () async {
    logger.info('kept', <String, Object?>{'bad': Object()});
    await logger.flush();

    expect(sink.single, contains('kept'));
    expect(sink.single, contains('unencodable data'));
  });

  test('logging stays non-blocking and bounded under load', () async {
    // Objective O5: the call site must not pay for persistence, and a burst
    // must not be able to exhaust memory.
    final Stopwatch stopwatch = Stopwatch()..start();

    for (int i = 0; i < 10000; i++) {
      logger.log(LogLevel.info, 'burst-$i', <String, Object?>{'i': i});
    }
    stopwatch.stop();

    expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    expect(logger.buffered, lessThanOrEqualTo(logger.capacity));
  });

  test('concurrent flushes collapse instead of double-writing', () async {
    final Completer<void> gate = Completer<void>();
    int calls = 0;
    final AppLogger slow = AppLogger(
      writer: (List<String> lines) async {
        calls++;
        await gate.future;
      },
      batchSize: 1000,
    );

    slow.info('one');
    final Future<void> first = slow.flush();
    slow.info('two');
    // The second flush arrives while the first is still awaiting the sink.
    await slow.flush();
    expect(calls, 1);

    gate.complete();
    await first;
    await slow.flush();
    expect(calls, 2, reason: 'the later batch is not lost');
  });

  test('dispose cancels the timer and drains what is left', () async {
    final AppLogger ticking = AppLogger(
      writer: _recordingSink(sink),
      flushInterval: const Duration(milliseconds: 5),
    )..start();

    ticking.info('before dispose');
    await ticking.dispose();

    expect(sink, hasLength(1));
    expect(ticking.buffered, 0);
  });
}
