import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';
import 'core/logging/app_logger.dart';

/// Bootstrap order matters:
///
///  1. Bindings, so the logger's file sink may use platform channels.
///  2. Validate configuration, so a build without credentials fails here with
///     an actionable message instead of surfacing later as a network error.
///  3. Start logging, so step 4's failure is itself recorded.
///  4. Initialise Supabase, which must complete before any provider resolves.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    Env.validate();
  } on AppConfigurationError catch (error, stackTrace) {
    runApp(ConfigurationErrorApp(message: error.message));
    debugPrint('$error');
    debugPrintStack(stackTrace: stackTrace);
    return;
  }

  await _installFileLogger();
  AppLogger.instance.start();
  AppLogger.instance.info('boot', {'version': '0.1.0', 'supabase': Env.supabaseUrl});

  try {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishableKey,
    );
  } catch (error, stackTrace) {
    AppLogger.instance.error('supabase initialisation failed', error, stackTrace);
    runApp(
      const ConfigurationErrorApp(
        message: 'Could not reach the Moaen backend. Please check your '
            'connection and try again.',
      ),
    );
    return;
  }

  runApp(const ProviderScope(child: MoaenApp()));
}

/// Points the logger at a real file. A failure here is not fatal: an in-memory
/// logger is still useful, and refusing to start over a log file would be the
/// wrong trade.
Future<void> _installFileLogger() async {
  try {
    final RollingFileLogWriter writer =
        await RollingFileLogWriter.inAppSupportDirectory();
    AppLogger.instance.useWriter(writer.call);
  } catch (error) {
    debugPrint('file logging unavailable, continuing in memory: $error');
  }
}

/// Shown when the app cannot start. Deliberately not routed through Riverpod
/// or the router, because the router's first dependency is the very thing that
/// just failed.
class ConfigurationErrorApp extends StatelessWidget {
  const ConfigurationErrorApp({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.build_outlined, size: 48),
                const SizedBox(height: 16),
                Text(
                  Env.appName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
