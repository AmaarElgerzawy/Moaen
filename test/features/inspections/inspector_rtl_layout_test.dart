import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moaen/core/localization/locale_provider.dart';
import 'package:moaen/core/theme/app_theme.dart';
import 'package:moaen/features/auth/auth_controller.dart';
import 'package:moaen/features/auth/user_profile.dart';
import 'package:moaen/features/inspections/application/inspection_controller.dart';
import 'package:moaen/features/inspections/domain/inspection_request.dart';
import 'package:moaen/features/inspections/presentation/inspector_home_page.dart';
import 'package:moaen/features/inspections/presentation/inspector_job_detail_page.dart';
import 'package:moaen/features/inspections/presentation/inspector_market_page.dart';
import 'package:moaen/features/inspections/presentation/widgets/design_widgets.dart';
import 'package:moaen/l10n/gen/app_localizations.dart';
import 'package:moaen/features/cities/application/city_controller.dart';

import '../../support/fake_cities.dart';
import '../../support/fake_inspection_repository.dart';

/// Layout assertions for the inspector screens under the Arabic, right-to-left
/// presentation — the mirror of `rtl_layout_test.dart` but for the inspector
/// side, with an inspector profile so the market header and the profile tab can
/// show the city the screens really run with.
///
/// Expected strings come from [AppLocalizations] rather than typed Arabic
/// literals, for the reasons stated in the client RTL test.
///
/// The fixtures here hold Arabic, unlike the English-flow tests. The production
/// city column is an Arabic name — RLS compares each request's city against the
/// inspector's — so a Latin fixture would assert the plumbing of a field the app
/// never actually stores, and the one assertion this file exists to make, that
/// Arabic cities reach an Arabic screen, could not be made at all.
const UserProfile _signedInInspector = UserProfile(
  id: 'inspector-1',
  fullName: 'كريم عادل',
  email: 'karim@example.com',
  role: UserRole.inspector,
  locationCity: 'الدمام',
  rating: 0,
);

class _StubAuthController extends AuthController {
  @override
  Future<UserProfile?> build() async => _signedInInspector;
}

/// Arabic script block, inclusive — reused here so a string can be asserted to
/// *be* Arabic rather than merely to match an expected glyph sequence.
final RegExp _arabicScript = RegExp(r'[\u0600-\u06FF]');

/// A repo holding one pending request in the inspector's city, so the board and
/// the detail have real content to lay out.
FakeInspectionRepository _withOneBoardRequest() => FakeInspectionRepository(
  requests: <InspectionRequest>[
    buildRequest(id: 'avail-1', referenceNo: 1005, city: 'الدمام'),
  ],
);

Widget _arabic(FakeInspectionRepository repository, Widget child) =>
    ProviderScope(
      overrides: [
        inspectionRepositoryProvider.overrideWithValue(repository),
        authControllerProvider.overrideWith(_StubAuthController.new),
        localeProvider.overrideWithValue(const Locale('ar')),
        citiesProvider.overrideWith((Ref ref) async => testCities),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // No explicit `Directionality` wrapper: `MaterialApp` with an Arabic
        // locale supplies it, and a wrapper would mask a screen that broke the
        // direction for itself.
        home: child,
      ),
    );

Widget _english(FakeInspectionRepository repository, Widget child) =>
    ProviderScope(
      overrides: [
        inspectionRepositoryProvider.overrideWithValue(repository),
        authControllerProvider.overrideWith(_StubAuthController.new),
        localeProvider.overrideWithValue(const Locale('en')),
        citiesProvider.overrideWith((Ref ref) async => testCities),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );

Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(420, 1600);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

AppLocalizations _l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first));

void main() {
  group('direction resolution', () {
    testWidgets('every inspector screen resolves to RTL in Arabic', (
      WidgetTester tester,
    ) async {
      for (final Widget page in <Widget>[
        const InspectorHomePage(),
        const InspectorJobDetailPage(id: 'avail-1'),
      ]) {
        await _pump(tester, _arabic(_withOneBoardRequest(), page));

        final BuildContext context = tester.element(find.byType(Scaffold).first);
        expect(
          Directionality.of(context),
          TextDirection.rtl,
          reason: '${page.runtimeType} did not resolve to RTL',
        );
      }
    });

    testWidgets('the same screens resolve to LTR in English', (
      WidgetTester tester,
    ) async {
      for (final Widget page in <Widget>[
        const InspectorHomePage(),
        const InspectorJobDetailPage(id: 'avail-1'),
      ]) {
        await _pump(tester, _english(_withOneBoardRequest(), page));

        expect(
          Directionality.of(tester.element(find.byType(Scaffold).first)),
          TextDirection.ltr,
          reason: '${page.runtimeType} did not resolve to LTR',
        );
      }
    });
  });

  group('the action belongs to the whole request', () {
    testWidgets('spans the detail width under RTL', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _arabic(_withOneBoardRequest(), const InspectorJobDetailPage(id: 'avail-1')),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      final Rect action = tester.getRect(
        find.widgetWithText(FilledButton, l10n.actionAccept),
      );
      final Rect card = tester.getRect(
        find.widgetWithText(TitledCard, l10n.cardCarTitle),
      );

      // A lone action is not a column of a form: it should span the same width
      // as the detail content it belongs to.
      expect(
        (action.width - card.width).abs(),
        lessThan(card.width * 0.05),
        reason: 'the accept action must span the detail content width',
      );
    });
  });

  group('the inspector chrome is Arabic', () {
    testWidgets('the header greets by name and the market pin names the city', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _arabic(_withOneBoardRequest(), const InspectorHomePage()));
      final AppLocalizations l10n = _l10nOf(tester);

      // The greeting is the profile's own name, so it is Arabic in the database
      // and Arabic on screen: nothing here is translated, and a screen that
      // reached for an English name would show the Latin one.
      expect(find.text(_signedInInspector.fullName), findsWidgets);
      expect(_arabicScript.hasMatch(_signedInInspector.fullName), isTrue);

      // The service city reaches the screen through the market's pin —
      // `📍 الدمام` — which is the only place the reference prints it. The task
      // board deliberately does not repeat it: Screen 4 has no such line, and an
      // inspector's own city is not part of a summary of somebody else's job.
      await _pump(
        tester,
        _arabic(_withOneBoardRequest(), const InspectorMarketPage()),
      );

      expect(find.text(l10n.marketLocation('الدمام')), findsWidgets);
      expect(
        _arabicScript.hasMatch(l10n.marketLocation('الدمام')),
        isTrue,
        reason: 'the Arabic bundle must not be serving English',
      );
      expect(find.text(l10n.marketLocation('Dammam')), findsNothing);
    });

    testWidgets('the navigation destinations are localized', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _arabic(_withOneBoardRequest(), const InspectorHomePage()));
      final AppLocalizations l10n = _l10nOf(tester);

      // Read inside the bar specifically: the selected tab's label also appears
      // as the screen's own heading, so a screen-wide finder would count both
      // and turn a passing localization into a false failure.
      Finder inNav(String label) => find.descendant(
        of: find.byType(AppBottomNav),
        matching: find.text(label),
      );

      // The reference's bar, in its order: المهام / الفحوصات / المحفظة / الملف.
      expect(inNav(l10n.navTasks), findsOneWidget);
      expect(inNav(l10n.navInspections), findsOneWidget);
      expect(inNav(l10n.navWallet), findsOneWidget);
      expect(inNav(l10n.navProfileTab), findsOneWidget);
      expect(inNav('Tasks'), findsNothing);
      expect(inNav('Inspections'), findsNothing);
      expect(inNav('Wallet'), findsNothing);
      expect(inNav('Profile'), findsNothing);
    });

    testWidgets('the detail labels the pending state and its action in Arabic', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _arabic(_withOneBoardRequest(), const InspectorJobDetailPage(id: 'avail-1')),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      expect(find.text(l10n.inspectorAvailableNote), findsOneWidget);
      expect(find.widgetWithText(FilledButton, l10n.actionAccept), findsOneWidget);
      expect(find.text('Accept inspection'), findsNothing);
      expect(_arabicScript.hasMatch(l10n.actionAccept), isTrue);
    });
  });
}