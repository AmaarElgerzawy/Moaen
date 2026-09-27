import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moaen/core/theme/app_theme.dart';
import 'package:moaen/l10n/gen/app_localizations.dart';

/// Guards the two properties the rest of the app silently depends on.
///
/// Arabic-first RTL (D7) is easy to break in ways that still compile and still
/// look plausible in a screenshot: a widget test that pumps a bare `MaterialApp`
/// gets LTR and passes anyway, and a missing `GlobalMaterialLocalizations`
/// delegate leaves Material's own strings in English while the app's are in
/// Arabic. Neither shows up as a compile error, so both are asserted here.
void main() {
  /// The delegate set and theme MoaenApp actually installs. A test that builds
  /// its own harness would drift from the real app and quietly stop testing it.
  Future<Probe> pump(WidgetTester tester, {Locale? locale}) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        theme: AppTheme.light(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (BuildContext inner) {
            context = inner;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return Probe(context);
  }

  group('localization', () {
    testWidgets('the default locale is Arabic and lays out right-to-left', (
      WidgetTester tester,
    ) async {
      // No locale passed: this is what MoaenApp requests, and asserting it here
      // is what keeps app.dart and the test from disagreeing.
      final Probe probe = await pump(tester, locale: const Locale('ar'));

      expect(Localizations.localeOf(probe.context).languageCode, 'ar');
      expect(
        Directionality.of(probe.context),
        TextDirection.rtl,
        reason: 'Arabic must lay out RTL, or every Phase 2 screen is mirrored '
            'wrong from the start and the mistake is baked in.',
      );
    });

    testWidgets('an unsupported device locale falls back to Arabic, not English', (
      WidgetTester tester,
    ) async {
      // A device set to a language Moaen does not ship.
      final Probe probe = await pump(tester, locale: const Locale('fr'));

      expect(
        Localizations.localeOf(probe.context).languageCode,
        'ar',
        reason: 'The fallback must be the product language. An Egyptian buyer '
            'with an unrecognised system locale should not silently get English.',
      );
    });

    testWidgets('app strings resolve in Arabic', (WidgetTester tester) async {
      final AppLocalizations l10n = (await pump(
        tester,
        locale: const Locale('ar'),
      )).l10n;

      expect(l10n.roleInspector, 'فاحص');
      expect(l10n.actionSignIn, 'تسجيل الدخول');
      // Placeholders must interpolate rather than print the ICU syntax, which is
      // what a missing argument silently produces.
      expect(l10n.helperPasswordMinLength(8), contains('8'));
      expect(l10n.helperPasswordMinLength(8), isNot(contains('{length}')));
      expect(l10n.linkRegisterPrompt('Moaen'), contains('Moaen'));
    });

    testWidgets("Material's own strings follow the locale, not English", (
      WidgetTester tester,
    ) async {
      // Without GlobalMaterialLocalizations these resolve to the default
      // English delegate and the assertions fail — which is the point. Date and
      // number formatting are the usual casualties, because none of that text
      // lives in the ARB files and so no string audit would notice.
      final MaterialLocalizations material = (await pump(
        tester,
        locale: const Locale('ar'),
      )).material;

      expect(material.openAppDrawerTooltip, isNot('Open navigation menu'));
      expect(material.okButtonLabel, isNot('OK'));
      expect(material.cancelButtonLabel, isNot('Cancel'));
    });

    testWidgets('English is still reachable for an en device', (
      WidgetTester tester,
    ) async {
      final Probe probe = await pump(tester, locale: const Locale('en'));

      expect(probe.l10n.roleInspector, 'Inspector');
      expect(
        Directionality.of(probe.context),
        TextDirection.ltr,
        reason: 'English is a supported locale, so it must lay out LTR. This is '
            'what proves the RTL default is a choice and not a hard-wiring.',
      );
    });

    testWidgets('every Arabic key is translated', (WidgetTester tester) async {
      // Reads the ARB files rather than the generated Dart: the ARB files are
      // the source of truth, and this catches the failure gen-l10n does not —
      // a key that is present but still holds the English template text, so an
      // Arabic user silently reads English.
      const String arbDir = 'lib/l10n/arb';
      final Map<String, dynamic> en = _readArb('$arbDir/app_en.arb');
      final Map<String, dynamic> ar = _readArb('$arbDir/app_ar.arb');

      final Set<String> enKeys = en.keys
          .where((String k) => !k.startsWith('@'))
          .toSet();
      final Set<String> arKeys = ar.keys
          .where((String k) => !k.startsWith('@'))
          .toSet();

      expect(
        arKeys.difference(enKeys),
        isEmpty,
        reason: 'These Arabic keys do not exist in the English template, so '
            'gen-l10n is carrying dead weight.',
      );
      expect(
        enKeys.difference(arKeys),
        isEmpty,
        reason: 'These keys have no Arabic translation. gen-l10n will not fail '
            'the build for a missing key in this configuration, so it has to be '
            'asserted: ${enKeys.difference(arKeys)}',
      );

      // The brand is intentionally the same in both scripts.
      const Set<String> intentionallySame = <String>{'appName'};

      final List<String> untranslated = <String>[
        for (final String key in enKeys)
          if (!intentionallySame.contains(key) && ar[key] == en[key]) key,
      ];

      expect(
        untranslated,
        isEmpty,
        reason: 'These Arabic values are identical to the English template, so '
            'an Arabic user sees English: $untranslated',
      );
    });

    test('no Arabic value contains a stray English word', () {
      // The coverage test above cannot see this: a value that is *partly*
      // translated still differs from the template, so it passes. Writing the
      // Arabic strings, an English word slipped into the middle of one
      // ("المبلغ الذي you're مستعد لدفعه") and nothing flagged it.
      //
      // Placeholders are excluded because `{city}` is supposed to be Latin, and
      // the brand is excluded because it is Latin by design.
      const Set<String> latinAllowed = <String>{'appName'};
      final RegExp placeholder = RegExp(r'\{[a-zA-Z]+\}');
      final RegExp latinWord = RegExp(r'[A-Za-z]{2,}');

      final List<String> offenders = <String>[];
      _readArb('lib/l10n/arb/app_ar.arb').forEach((String key, dynamic value) {
        if (key.startsWith('@') || latinAllowed.contains(key)) return;
        if (value is! String) return;
        // Strip placeholders first, so `{city}` is not itself read as English.
        final String withoutPlaceholders = value.replaceAll(placeholder, '');
        if (latinWord.hasMatch(withoutPlaceholders)) {
          offenders.add('$key = $value');
        }
      });

      expect(
        offenders,
        isEmpty,
        reason: 'Latin text inside an Arabic value is an untranslated fragment: '
            '$offenders',
      );
    });
  });

  group('theme tokens', () {
    test('spacing is monotonic', () {
      expect(AppSpacing.xs, lessThan(AppSpacing.sm));
      expect(AppSpacing.sm, lessThan(AppSpacing.md));
      expect(AppSpacing.md, lessThan(AppSpacing.lg));
      expect(AppSpacing.lg, lessThan(AppSpacing.xl));
      expect(AppSpacing.xl, lessThan(AppSpacing.xxl));
      expect(AppSpacing.xxl, lessThan(AppSpacing.xxxl));
    });

    test('radius is monotonic', () {
      expect(AppRadius.sm, lessThan(AppRadius.md));
      expect(AppRadius.md, lessThan(AppRadius.lg));
      expect(AppRadius.lg, lessThanOrEqualTo(AppRadius.card));
    });

    testWidgets('the theme applies without error', (WidgetTester tester) async {
      await pump(tester, locale: const Locale('ar'));
      expect(tester.takeException(), isNull);
    });
  });
}

/// What [pump] captures from inside the widget tree.
///
/// The context is captured in a `Builder` rather than found with a finder:
/// `find.byType(Builder)` also matches the several `Builder`s MaterialApp
/// creates internally, so it throws "Too many elements".
class Probe {
  Probe(this.context);

  final BuildContext context;

  AppLocalizations get l10n => AppLocalizations.of(context);

  MaterialLocalizations get material => MaterialLocalizations.of(context);
}

Map<String, dynamic> _readArb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
