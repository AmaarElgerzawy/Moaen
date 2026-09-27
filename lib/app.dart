import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/env.dart';
import 'core/logging/app_logger.dart';
import 'core/router/app_router.dart';

class MoaenApp extends ConsumerStatefulWidget {
  const MoaenApp({super.key});

  @override
  ConsumerState<MoaenApp> createState() => _MoaenAppState();
}

class _MoaenAppState extends ConsumerState<MoaenApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A mobile app spends most of its life suspended, and the periodic drain
    // does not run while it is. Flushing on the way out is what makes the log
    // file useful for diagnosing a crash that happened before the next tick.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(AppLogger.instance.flush());
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: Env.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0E6B55),
        useMaterial3: true,
      ),
      // Arabic and RTL arrive with the Phase 2 screens, together with
      // flutter_localizations. MaterialApp's default English delegates are
      // correct until then. See PROJECT_MAP.md P6.
    );
  }
}
