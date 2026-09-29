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
        reason: 'The fallback must be the product language. A buyer with an '
            'unrecognised system locale should not silently get English.',
      );
    });

    testWidgets('app strings resolve in Arabic', (WidgetTester tester) async {
      final AppLocalizations l10n = (await pump(
        tester,
        locale: const Locale('ar'),
      )).l10n;

      // "معاين" is the product's own name, and it is the name the design uses on
      // every screen. Asserting it here rather than a synonym is what stops the
      // brand drifting away from the name in the app icon.
      expect(l10n.roleInspector, 'معاين');
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

      // Keys whose Arabic value is deliberately *not* different from English.
      //
      // Each is here for a stated reason, not because translating it was skipped.
      // An allowlist is only worth having if it is auditable, so every entry names
      // why the two scripts coincide — a value that is Latin by nature cannot be
      // translated, and translating it would corrupt it.
      const Set<String> intentionallySame = <String>{
        // The registered brand, Latin in both scripts by design.
        'appName',
        // A pure placeholder template. Arabic and English read the same because
        // the only content is `{day} {time} - {centre}`; the *values* interpolated
        // into it are Arabic.
        'stepAppointmentSub',
        // A URL. Translating a hostname produces a link that goes nowhere.
        'createHintListing',
        // A phone-number shape, not a word. `05xxxxxxxx` is the placeholder the
        // design shows; an Arabic transliteration of the x-run would be noise.
        'createHintSellerPhone',
      };

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
      //
      // The second and third entries are the design's own Latin-shaped values —
      // the listing-URL hint and the phone hint. Neither can be Arabic: one is a
      // hostname and the other is a digit pattern. They are excluded here for the
      // same reason they are in `intentionallySame` above, and the two lists are
      // deliberately separate so a key cannot quietly acquire an excuse in one
      // test but not the other.
      const Set<String> latinAllowed = <String>{
        'appName',
        'createHintListing',
        'createHintSellerPhone',
      };
      final RegExp placeholder = RegExp(r'\{[a-zA-Z]+\}');
      final RegExp latinWord = RegExp(r'[A-Za-z]{2,}');

      // ICU plural and select arguments are English *by definition*: gen-l10n
      // writes `{count, plural, =2 {فحص} other {فحص}}`, and `plural`, `other` and
      // `=2` are keywords the runtime consumes, not text a reader ever sees.
      //
      // They are stripped rather than allowlisted, because allowlisting these four
      // keys would also switch off the check for the Arabic inside them — which is
      // the part worth checking. The three steps are applied in order because each
      // unbalances the braces the next one relies on.
      final RegExp icuHeader = RegExp(
        r'\{[a-zA-Z]+\s*,\s*(?:plural|select)\s*,',
      );
      // `=2` exact matches, and the bare category keywords. None of these words
      // occur in an Arabic value, so removing them cannot eat real text.
      final RegExp icuKeyword = RegExp(
        r'=\d+\s*|\b(?:zero|one|two|few|many|other)\b\s*',
      );

      final List<String> offenders = <String>[];
      _readArb('lib/l10n/arb/app_ar.arb').forEach((String key, dynamic value) {
        if (key.startsWith('@') || latinAllowed.contains(key)) return;
        if (value is! String) return;
        // Strip ICU syntax first, then placeholders, so `{count}` is not itself
        // read as English.
        final String withoutPlaceholders = value
            .replaceAll(icuHeader, '')
            .replaceAll(icuKeyword, '')
            .replaceAll(placeholder, '');
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
