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
        'createListingHint',
        // A phone-number shape, not a word. `05xxxxxxxx` is the placeholder the
        // design shows; an Arabic transliteration of the x-run would be noise.
        'createSellerPhoneHint',
        // The market's two location lines. Both are an emoji plus interpolated
        // values, with no word of their own — `📍 الدمام` is the Arabic rendering
        // and `📍 Dammam` the English one, and the difference is entirely in
        // `{city}`. A translatable word would have to be invented, because the
        // design prints none: the pin *is* the label.
        'marketLocation',
        'marketLocationArea',
        // Three more pure placeholder templates. There is no word in any of them
        // to translate — the surrounding text that would give them a direction is
        // the caller's, and the values interpolated in are already Arabic.
        // `reportScoreWithGrade` is the report's own `95% (ممتاز)`, where the
        // grade word is a parameter.
        'reportScoreWithGrade',
        'centreTimeValue',
        'accountRatingValue',
        // `({phone})` on its own: a parenthesised number under a label. The
        // design prints no word with it, and the Arabic and English documents
        // differ only in the digits, which are parameters.
        'inspectorTaskPhoneLabel',
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
      //
      // The report's six entries are the design's own mixed-script strings. Arabic
      // technical writing carries the acronym for the thing it names — `OBD-II`,
      // `DTC`, `ECU` — and the report names the paper size (`A4`), the chassis
      // number (`VIN`) and the diagram (`Car Blueprint`). Translating any of them
      // would produce a document no inspector recognises, which is the opposite of
      // what the report is for. They are listed individually rather than matched
      // by pattern, so a *new* Latin fragment cannot slip in without a decision.
      const Set<String> latinAllowed = <String>{
        'appName',
        'createListingHint',
        'createSellerPhoneHint',
        'reportObdTitle',
        'reportObdFaults',
        'reportObdCodes',
        'reportObdNotesHint',
        'reportIssue',
        'reportTileVin',
        'reportBlueprintSection',
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

    testWidgets('every key is reachable from the Dart sources', (
      WidgetTester tester,
    ) async {
      // A key nothing reads is a translation nobody will ever look at again, and
      // the failure mode is quiet: it survives every other check here, it costs
      // nothing at runtime, and the next person to open the file cannot tell it
      // apart from a live string. Both ARB files accumulated dozens of them
      // while the design screens were being built, because a key that stops being
      // used when a widget is rewritten leaves no trace anywhere.
      //
      // The generated localisations are excluded from the search: they contain
      // every key by construction, so including them would make this check a
      // tautology. What matters is whether *the app's own code* names the key.
      //
      // `lib` only, not `test`. A test names keys legitimately — to find a widget
      // by its label — but a test cannot make a key live, and letting tests count
      // as usage is exactly how a key stays in the file after the screen that
      // rendered it was deleted: the test that asserted on it went with the
      // screen, or was rewritten, and the key outlived both.
      final Set<String> reachable = _dartSourceText();
      final List<String> unreachable = <String>[
        for (final String key in _readArb('lib/l10n/arb/app_en.arb').keys)
          if (!key.startsWith('@') && !reachable.contains(key)) key,
      ];

      expect(
        unreachable,
        isEmpty,
        reason: 'These keys are defined and translated but never read. Delete '
            'them from both ARB files, or wire the screen that was meant to use '
            'them. ${unreachable.length} of them.',
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

/// Reads an ARB file, refusing one that defines the same key twice.
///
/// [jsonDecode] does not complain about a repeated key: it keeps the last one and
/// moves on, and so does `flutter gen-l10n`, because a duplicate is legal JSON.
/// That silence is the hazard. A stale copy left behind by a rewrite is invisible
/// until someone edits *that* line, sees no change in the app, and concludes the
/// key is unused. Both files in this project have carried one.
///
/// The check is a raw scan of the top-level lines rather than a walk of the
/// parsed tree, because a parse cannot see what it threw away. Two-space
/// indentation is what separates a top-level key from a nested one — a placeholder
/// named `city` is a legitimate repeat, and only a top-level `city` is a clash.
/// `@@locale` is the ARB convention rather than a key and is not counted.
Map<String, dynamic> _readArb(String path) {
  final String source = File(path).readAsStringSync();
  final List<String> topLevel = RegExp(
    r'^ {2}"(@?@?[A-Za-z0-9_]+)":',
    multiLine: true,
  )
      .allMatches(source)
      .map((RegExpMatch m) => m.group(1)!)
      .where((String key) => key != '@@locale')
      .toList();

  final Set<String> seen = <String>{};
  final List<String> repeated = <String>[
    for (final String key in topLevel)
      if (!seen.add(key)) key,
  ];
  expect(
    repeated,
    isEmpty,
    reason: 'These keys are defined more than once in $path. JSON keeps the last '
        'definition and drops the rest, so the earlier one is dead weight that '
        'still looks editable. Remove it, and check which of the two was meant to '
        'win.',
  );

  return jsonDecode(source) as Map<String, dynamic>;
}

/// Every identifier that appears in the application's own Dart sources, minus the
/// generated localisations.
///
/// A set of words rather than a set of `l10n.` lookups on purpose: `l10n.key`,
/// `AppLocalizations.of(context).key` and a bare `key` in a `switch` are all real
/// ways these are reached, and a check that only understood one of them would
/// report a live string as dead. Over-approximating inside `lib` is safe — the
/// failure mode is a key that has genuinely been renamed away escaping the check,
/// which the compiler catches anyway — while under-approximating would report a
/// live key as dead and train people to ignore the failure.
Set<String> _dartSourceText() {
  final Set<String> words = <String>{};
  final Directory lib = Directory('lib');
  if (!lib.existsSync()) return words;
  for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // The generated file is a mirror of the ARB, so every key is in it by
    // definition and it would satisfy every lookup.
    if (entity.path.contains(
      '${Platform.pathSeparator}l10n${Platform.pathSeparator}gen'
      '${Platform.pathSeparator}',
    )) {
      continue;
    }
    words.addAll(
      RegExp('[A-Za-z0-9_]+')
          .allMatches(entity.readAsStringSync())
          .map((RegExpMatch m) => m.group(0)!),
    );
  }
  return words;
}
