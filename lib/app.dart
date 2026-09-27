import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/env.dart';
import 'core/localization/locale_provider.dart';
import 'core/logging/app_logger.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'l10n/gen/app_localizations.dart';

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
    // Arabic is the product's first language (D7), so it is also the fallback: a
    // device set to a language Moaen does not ship gets Arabic rather than
    // English, because an Egyptian buyer with an Arabic phone and an
    // unrecognised system locale should not silently get the wrong language.
    final Locale locale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: Env.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light(),

      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        // Without these the Material widgets keep English defaults even when the
        // app strings are Arabic: date and number pickers, the text-selection
        // menu, and the semantic labels on every built-in control. That produces
        // an app that is half-translated in a way no string audit would catch,
        // because none of the offending text is in the ARB files.
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // No Directionality override here. MaterialApp already resolves the locale
      // and applies the matching text direction to the whole tree, so a manual
      // wrapper would be a second source of truth that could disagree with the
      // first. test/core/localization_test.dart asserts the direction instead.
    );
  }
}
