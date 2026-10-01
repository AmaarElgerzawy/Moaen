import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moaen/core/localization/locale_provider.dart';
import 'package:moaen/core/theme/app_theme.dart';
import 'package:moaen/features/auth/auth_controller.dart';
import 'package:moaen/features/auth/auth_repository.dart';
import 'package:moaen/features/auth/user_profile.dart';
import 'package:moaen/features/cities/application/city_controller.dart';
import 'package:moaen/features/inspections/application/inspection_controller.dart';
// Not transitive from the fake: Dart imports are per-library, so a test that
// constructs an `InspectionFailure` has to name where it comes from.
import 'package:moaen/features/inspections/data/inspection_repository.dart';
import 'package:moaen/features/inspections/domain/inspection_request.dart';
import 'package:moaen/features/inspections/presentation/inspector_home_page.dart';
import 'package:moaen/features/inspections/presentation/inspector_job_detail_page.dart';
import 'package:moaen/features/inspections/presentation/inspector_market_page.dart';
import 'package:moaen/features/inspections/presentation/report_entry_page.dart';
import 'package:moaen/features/inspections/presentation/widgets/design_widgets.dart';
import 'package:moaen/l10n/gen/app_localizations.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_cities.dart';
import '../../support/fake_inspection_repository.dart';

/// Widget tests for the inspector side: the market, the four tabs of the home
/// shell, the wallet arithmetic and the request detail with its three status
/// actions.
///
/// Rendered in English deliberately, like the client flow tests: these assert
/// behaviour — which action a status offers, what happens when it is taken.
/// The Arabic and RTL rendering is covered by
/// `test/features/inspections/inspector_rtl_layout_test.dart` and the shared
/// localization audit.
///
/// The [id] must match the fake repository's [FakeInspectionRepository
/// .assignedInspectorId] default, the way the trigger would bind
/// `inspector_id := auth.uid()` in the real database.
const UserProfile _signedInInspector = UserProfile(
  id: 'inspector-1',
  fullName: 'Karim Adel',
  email: 'karim@example.com',
  role: UserRole.inspector,
  locationCity: 'Dammam',
  rating: 4.5,
);

class _StubAuthController extends AuthController {
  @override
  Future<UserProfile?> build() async => _signedInInspector;
}

/// An inspector with no ratings yet, for the profile rating fallback.
const UserProfile _unratedInspector = UserProfile(
  id: 'inspector-1',
  fullName: 'Karim Adel',
  email: 'karim@example.com',
  role: UserRole.inspector,
  locationCity: 'Dammam',
);

class _UnratedAuthController extends AuthController {
  @override
  Future<UserProfile?> build() async => _unratedInspector;
}

Widget _app(
  FakeInspectionRepository repository, {
  required Widget child,
  Locale locale = const Locale('en'),
  AuthRepository? authRepository,
}) => ProviderScope(
  overrides: [
    inspectionRepositoryProvider.overrideWithValue(repository),
    authControllerProvider.overrideWith(_StubAuthController.new),
    // The profile tab can change the service city, which routes through the
    // auth repository. The default fake records the call instead of touching a
    // network; tests that care pass their own instance.
    authRepositoryProvider.overrideWithValue(
      authRepository ??
          FakeAuthRepository(
            profile: _signedInInspector,
            userId: _signedInInspector.id,
          ),
    ),
    localeProvider.overrideWithValue(locale),
    // The city editor opens the canonical-city picker, which reads the city
    // list; overridden so the picker never reaches a network.
    citiesProvider.overrideWith((Ref ref) async => testCities),
  ],
  child: MaterialApp(
    locale: locale,
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  ),
);

/// The market and the job detail under one router, so the tap-through between
/// them is exercised rather than stubbed — the market's card pushes the detail
/// page by name, and a test that mounted the two as separate trees would pass
/// while the real route stayed wrong.
Widget _flowApp(
  FakeInspectionRepository repository, {
  Widget start = const InspectorHomePage(),
}) => ProviderScope(
  overrides: [
    inspectionRepositoryProvider.overrideWithValue(repository),
    authControllerProvider.overrideWith(_StubAuthController.new),
    authRepositoryProvider.overrideWithValue(
      FakeAuthRepository(
        profile: _signedInInspector,
        userId: _signedInInspector.id,
      ),
    ),
    localeProvider.overrideWithValue(const Locale('en')),
    citiesProvider.overrideWith((Ref ref) async => testCities),
  ],
  child: MaterialApp.router(
    locale: const Locale('en'),
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => start),
        GoRoute(
          path: '/inspector/market',
          name: 'inspectorMarket',
          builder: (_, _) => const InspectorMarketPage(),
        ),
        GoRoute(
          path: '/inspector/jobs/:id',
          // The production name, not a test-only alias: the market pushes this
          // by name, and a test router that renamed it would stop proving the
          // name is right.
          name: 'inspectorJob',
          builder: (_, GoRouterState state) =>
              InspectorJobDetailPage(id: state.pathParameters['id'] ?? ''),
        ),
        GoRoute(
          path: '/requests/:id/report/entry',
          name: 'reportEntry',
          builder: (_, GoRouterState state) =>
              ReportEntryPage(id: state.pathParameters['id'] ?? ''),
        ),
      ],
    ),
  ),
);

/// The bottom-nav item with [label].
///
/// Scoped to the bar, because a tab's own `ShellHeader` repeats the same word:
/// `الفحوصات` is both the second nav destination and the title of the screen it
/// opens, and a screen-wide finder would find two and report `findsOneWidget` as
/// a failure — which reads as a bug in the shell rather than in the finder.
Finder navItem(String label) => find.descendant(
  of: find.byType(AppBottomNav),
  matching: find.text(label),
);

/// Pops the current route the way the platform would.
///
/// Not [WidgetTester.pageBack], which looks for a back button widget and finds
/// none: these pushed screens carry the design's own dark header rather than a
/// Material `AppBar`, so the only way off them is the system gesture. Driving the
/// system route pop is therefore closer to what a person does than tapping a
/// button that this app does not have — and it means a test here cannot pass by
/// finding a back affordance the design never drew.
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

/// The market's header pin, for a page whose localizations are [l10n].
///
/// The same string appears on every listing — `📍 {city} | طالب الفحص: …` — so
/// the header is read by its position rather than by its text, and a test
/// asserting "the market is scoped to this city" is asserting about the header
/// specifically, not about every pin on the page.
Finder marketHeaderCity(AppLocalizations l10n, String city) =>
    find.descendant(
      of: find.byType(DarkHeader),
      matching: find.text(l10n.marketLocation(city)),
    );

/// Pumps [app] on a surface tall enough for the full detail page.
///
/// Not cosmetic: the default test surface is 800x600 and the detail page is
/// far taller, so the action section would sit below the fold — invisible to
/// `find` and untappable.
Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1000, 3400);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

void main() {
  group('InspectorMarketPage · the market', () {
    testWidgets('lists only requests still waiting to be claimed', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(
            id: 'avail-1',
            referenceNo: 1005,
            make: 'Lexus',
            model: 'ES350',
            year: 2022,
          ),
          buildRequest(
            id: 'avail-2',
            referenceNo: 1004,
            make: 'Nissan',
            model: 'Patrol',
            year: 2021,
          ),
          buildRequest(
            id: 'mine-1',
            referenceNo: 1003,
            inspectorId: 'inspector-1',
            status: InspectionStatus.accepted,
          ),
        ],
      );
      await _pump(
        tester,
        _app(repository, child: const InspectorMarketPage()),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      // The reference identifies a listing by the car, not by a reference number:
      // an inspector choosing between jobs reads the make and the district, and
      // `MN-1005` appears nowhere on this screen.
      expect(find.text('Lexus ES350 (2022)'), findsOneWidget);
      expect(find.text('Nissan Patrol (2021)'), findsOneWidget);
      expect(
        find.text('Toyota Corolla (2019)'),
        findsNothing,
        reason: 'a claimed request is not available to be claimed',
      );
      expect(find.text('MN-1005'), findsNothing);
      // The fee is the same one price list the buyer's invoice quotes.
      expect(find.text('+150'), findsNWidgets(2));
      expect(find.text(l10n.marketFeeLabel), findsNWidgets(2));
    });

    testWidgets('an empty market says so and names the city', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _app(FakeInspectionRepository(), child: const InspectorMarketPage()),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      expect(find.text(l10n.marketEmptyTitle), findsOneWidget);
      expect(find.text(l10n.marketEmptyBody('Dammam')), findsOneWidget);
    });

    testWidgets('a failed market load is retryable', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(
            id: 'avail-1',
            referenceNo: 1005,
            make: 'Lexus',
            model: 'ES350',
          ),
        ],
        failure: const InspectionFailure('boom'),
      );
      await _pump(
        tester,
        _app(repository, child: const InspectorMarketPage()),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      expect(find.text(l10n.tabLoadError), findsOneWidget);
      expect(find.text('Lexus ES350 (2019)'), findsNothing);

      // `DesignRetry` outlines its action, not fills it: a retry is a fallback,
      // not the screen's primary action, and filling it would outrank the thing
      // the inspector came to do.
      repository.failure = null;
      await tester.tap(find.widgetWithText(OutlinedButton, l10n.actionRetry));
      await tester.pumpAndSettle();

      expect(find.text('Lexus ES350 (2019)'), findsOneWidget);
    });

    testWidgets('accepting from the market takes the request', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[buildRequest(id: 'avail-1', referenceNo: 1005)],
      );
      await _pump(
        tester,
        _app(repository, child: const InspectorMarketPage()),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      // The market's own button, not the detail page's. It asks first, exactly as
      // the detail page's does: two routes to the same commitment have to weigh
      // the same, or an inspector learns the question by being surprised.
      await tester.tap(find.widgetWithText(FilledButton, l10n.marketAccept));
      await tester.pumpAndSettle();

      expect(find.text(l10n.acceptConfirmTitle), findsOneWidget);
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, l10n.actionAccept),
      ));
      await tester.pumpAndSettle();

      expect(repository.acceptedIds, <String>['avail-1']);
      // The board query is scoped to unclaimed rows, so the listing is gone from
      // under the inspector who just took it.
      expect(find.text(l10n.marketEmptyTitle), findsOneWidget);
    });

    testWidgets('a confirmation declined on the market takes nothing', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[buildRequest(id: 'avail-1', referenceNo: 1005)],
      );
      await _pump(
        tester,
        _app(repository, child: const InspectorMarketPage()),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      await tester.tap(find.widgetWithText(FilledButton, l10n.marketAccept));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, l10n.actionKeep),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.acceptedIds, isEmpty);
      // Still listed, still available: a request nobody took has not gone away.
      expect(find.text('Toyota Corolla (2019)'), findsOneWidget);
    });
  });

  group('InspectorHomePage · the tasks tab', () {
    testWidgets('the current task is the accepted job, not the finished one', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(
            id: 'mine-1',
            referenceNo: 1003,
            inspectorId: 'inspector-1',
            status: InspectionStatus.inProgress,
            make: 'Toyota',
            model: 'FJ',
            year: 2023,
          ),
          buildRequest(
            id: 'mine-2',
            referenceNo: 1002,
            inspectorId: 'inspector-1',
            status: InspectionStatus.accepted,
            make: 'Lexus',
            model: 'ES350',
            year: 2022,
          ),
          buildRequest(
            id: 'done-1',
            referenceNo: 1001,
            inspectorId: 'inspector-1',
            status: InspectionStatus.completed,
          ),
        ],
      );
      await _pump(tester, _app(repository, child: const InspectorHomePage()));
      final AppLocalizations l10n = _l10nOf(tester);

      // The card the reference draws is the one whose subject is a booking, so the
      // accepted job wins over the one already under way. Asserting only that
      // *some* live job is shown would pass against a picker that took the first
      // row, which is the in-progress one here.
      expect(find.text('Lexus ES350 (2022)'), findsOneWidget);
      expect(find.text('Toyota FJ (2023)'), findsNothing);
      expect(find.text(l10n.centreBoxTitle), findsOneWidget);
    });

    testWidgets('no current task points at the market', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _app(FakeInspectionRepository(), child: const InspectorHomePage()),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      expect(find.text(l10n.inspectorNoCurrentTask), findsOneWidget);
      expect(find.text(l10n.inspectorNoCurrentTaskBody), findsOneWidget);
      expect(find.text(l10n.centreBoxTitle), findsNothing);
      // The way to the market is on this screen; without it the empty state is a
      // dead end. Read as a `Text` inside a `TextButton` — a bare text finder
      // would also match the market's own accept label on a populated board.
      expect(
        find.descendant(
          of: find.byType(TextButton),
          matching: find.text(l10n.marketViewAll),
        ),
        findsOneWidget,
        reason: 'the empty current-task state must offer the market',
      );
    });

    testWidgets('the earnings row counts completed jobs at the fixed fee', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(
            id: 'done-1',
            referenceNo: 1001,
            inspectorId: 'inspector-1',
            status: InspectionStatus.completed,
          ),
          buildRequest(
            id: 'done-2',
            referenceNo: 1002,
            inspectorId: 'inspector-1',
            status: InspectionStatus.completed,
          ),
          buildRequest(
            id: 'live-1',
            referenceNo: 1003,
            inspectorId: 'inspector-1',
            status: InspectionStatus.accepted,
          ),
        ],
      );
      await _pump(tester, _app(repository, child: const InspectorHomePage()));
      final AppLocalizations l10n = _l10nOf(tester);

      // Read inside the stats bar. The design uses the same word twice on this
      // screen — the bar's middle column is `الفحوصات` and so is the second nav
      // destination — so a screen-wide finder would find two and read as a
      // failure in the shell. The collision is the reference's, not this build's.
      Finder inStats(String text) => find.descendant(
        of: find.byType(StatsBar),
        matching: find.text(text),
      );

      expect(inStats(l10n.statRequestFee), findsOneWidget);
      expect(inStats(l10n.statInspections), findsOneWidget);
      expect(inStats(l10n.statEarningsToday), findsOneWidget);
      // 150 per completed job, two of them, and the in-progress one is not
      // counted — earnings are for work that finished.
      expect(inStats('ر.س 150'), findsOneWidget);
      expect(inStats('2 inspections'), findsOneWidget);
      expect(inStats('ر.س 300'), findsOneWidget);
    });
  });

  group('InspectorJobDetailPage · actions follow the status', () {
    testWidgets('a pending request offers accept, and nothing else', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[buildRequest(id: 'avail-1', referenceNo: 1005)],
      );
      await _pump(
        tester,
        _app(repository, child: const InspectorJobDetailPage(id: 'avail-1')),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      expect(find.text('MN-1005'), findsOneWidget);
      expect(find.text(l10n.inspectorAvailableNote), findsOneWidget);
      expect(find.widgetWithText(FilledButton, l10n.actionAccept), findsOneWidget);
      expect(find.widgetWithText(FilledButton, l10n.actionStart), findsNothing);
      expect(find.widgetWithText(FilledButton, l10n.actionComplete), findsNothing);
    });

    testWidgets('accepting takes the request after a confirmation', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(
            id: 'avail-1',
            referenceNo: 1005,
            make: 'Lexus',
            model: 'ES350',
            year: 2022,
          ),
        ],
      );
      await _pump(
        tester,
        _flowApp(repository, start: const InspectorMarketPage()),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      // The market's card is the way into the job: the reference draws a listing
      // with no navigation of its own, and a card naming a car, a district and a
      // fee that cannot be opened is a card that reads as a link.
      await tester.tap(find.text('Lexus ES350 (2022)'));
      await tester.pumpAndSettle();

      expect(find.byType(InspectorJobDetailPage), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, l10n.actionAccept));
      await tester.pumpAndSettle();

      // The page action and the dialog action share the same label, so the
      // dialog's button is found inside the dialog, not on screen-wide text.
      expect(find.text(l10n.acceptConfirmTitle), findsOneWidget);
      expect(find.text(l10n.acceptConfirmBody('Dammam')), findsOneWidget);
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, l10n.actionAccept),
      ));
      await tester.pumpAndSettle();

      expect(repository.acceptedIds, <String>['avail-1']);
      expect(find.text(l10n.inspectorAccepted), findsOneWidget);
      // The invalidated detail refetched: the request is now the inspector's,
      // so the action has moved from accept to start.
      expect(find.widgetWithText(FilledButton, l10n.actionStart), findsOneWidget);
      expect(find.text(l10n.inspectorAssignedNote), findsOneWidget);

      // Back in the market, the claimed request is gone — the board query is
      // scoped to unclaimed rows, so the listing disappears on its own.
      await _systemBack(tester);
      expect(find.text('Lexus ES350 (2022)'), findsNothing);
      expect(find.text(l10n.marketEmptyTitle), findsOneWidget);
    });

    testWidgets('an accepted request offers start', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(
            id: 'mine-1',
            referenceNo: 1003,
            inspectorId: 'inspector-1',
            status: InspectionStatus.accepted,
          ),
        ],
      );
      await _pump(
        tester,
        _app(repository, child: const InspectorJobDetailPage(id: 'mine-1')),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      expect(find.widgetWithText(FilledButton, l10n.actionStart), findsOneWidget);
      expect(find.widgetWithText(FilledButton, l10n.actionAccept), findsNothing);
      expect(find.widgetWithText(FilledButton, l10n.actionComplete), findsNothing);
    });

    testWidgets('starting moves the job to in progress', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(
            id: 'mine-1',
            referenceNo: 1003,
            inspectorId: 'inspector-1',
            status: InspectionStatus.accepted,
          ),
        ],
      );
      await _pump(
        tester,
        _app(repository, child: const InspectorJobDetailPage(id: 'mine-1')),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      await tester.tap(find.widgetWithText(FilledButton, l10n.actionStart));
      await tester.pumpAndSettle();

      expect(repository.startedIds, <String>['mine-1']);
      expect(find.text(l10n.inspectorStarted), findsOneWidget);
      // The refetched row is now in progress, offering complete.
      expect(find.widgetWithText(FilledButton, l10n.actionComplete), findsOneWidget);
      expect(find.text(l10n.statusInProgress), findsOneWidget);
    });

    testWidgets('completing finishes the job after a confirmation', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(
            id: 'mine-1',
            referenceNo: 1003,
            inspectorId: 'inspector-1',
            status: InspectionStatus.inProgress,
            make: 'Toyota',
            model: 'FJ',
            year: 2023,
            notes: 'The rear bumper is resprayed.',
          ),
        ],
      );
      // Under the router, because finishing a job pushes the report form: a test
      // that mounted the detail page as a bare `home` would throw on the push
      // rather than reach the screen that follows it.
      await _pump(tester, _flowApp(repository));
      final AppLocalizations l10n = _l10nOf(tester);

      await tester.tap(navItem(l10n.navInspections));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Toyota FJ (2023)'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, l10n.actionComplete));
      await tester.pumpAndSettle();

      expect(find.text(l10n.completeConfirmTitle), findsOneWidget);
      expect(find.text(l10n.completeConfirmBody), findsOneWidget);
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, l10n.actionComplete),
      ));
      await tester.pumpAndSettle();

      expect(repository.completedIds, <String>['mine-1']);
      expect(find.text(l10n.inspectorCompleted), findsOneWidget);
      // Finishing is not the end of the job: the report form opens over the
      // detail, because the inspector's next task is writing the report and a
      // separate "now go and do that" step would be one more tap for nothing.
      expect(find.byType(ReportEntryPage), findsOneWidget);
    });

    testWidgets('a settled job offers no action and says so', (
      WidgetTester tester,
    ) async {
      // Mounted directly rather than reached by completing one: the completed
      // fixture is the settled state itself, and re-deriving it by taking the
      // same action twice would only re-test the action.
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(
            id: 'done-1',
            referenceNo: 1002,
            inspectorId: 'inspector-1',
            status: InspectionStatus.completed,
          ),
        ],
      );
      await _pump(
        tester,
        _app(repository, child: const InspectorJobDetailPage(id: 'done-1')),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      expect(find.widgetWithText(FilledButton, l10n.actionComplete), findsNothing);
      expect(find.widgetWithText(FilledButton, l10n.actionStart), findsNothing);
      expect(find.widgetWithText(FilledButton, l10n.actionAccept), findsNothing);
      expect(find.text(l10n.inspectorSettledNote), findsOneWidget);
    });

    testWidgets('declining a confirmation changes nothing', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[buildRequest(id: 'avail-1', referenceNo: 1005)],
      );
      await _pump(
        tester,
        _app(repository, child: const InspectorJobDetailPage(id: 'avail-1')),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      await tester.tap(find.widgetWithText(FilledButton, l10n.actionAccept));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.actionKeep));
      await tester.pumpAndSettle();

      expect(repository.acceptedIds, isEmpty);
      expect(find.text(l10n.inspectorAccepted), findsNothing);
      // Still pending, still accepting.
      expect(find.widgetWithText(FilledButton, l10n.actionAccept), findsOneWidget);
    });

    testWidgets('an accept that loses a race is reported as taken', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[buildRequest(id: 'avail-1', referenceNo: 1005)],
      )..acceptFailure = const InspectionFailure(
        'Another inspector just took this request.',
      );
      await _pump(
        tester,
        _app(repository, child: const InspectorJobDetailPage(id: 'avail-1')),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Accept inspection'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Accept inspection'),
      ));
      await tester.pumpAndSettle();

      // The failure is surfaced, not swallowed, and the status is unchanged.
      expect(find.text('Another inspector just took this request.'), findsOneWidget);
      expect(find.text('Inspection accepted.'), findsNothing);
    });
  });

  group('InspectorHomePage · the inspections tab', () {
    testWidgets('lists this inspector’s jobs, settled and open alike', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(
            id: 'open-1',
            referenceNo: 1003,
            inspectorId: 'inspector-1',
            status: InspectionStatus.inProgress,
            make: 'Toyota',
            model: 'FJ',
            year: 2023,
          ),
          buildRequest(
            id: 'done-1',
            referenceNo: 1002,
            inspectorId: 'inspector-1',
            status: InspectionStatus.completed,
            make: 'Lexus',
            model: 'ES350',
            year: 2022,
          ),
          // Another inspector's job must not appear at all.
          buildRequest(
            id: 'theirs-1',
            referenceNo: 1001,
            inspectorId: 'inspector-2',
            status: InspectionStatus.accepted,
            make: 'Nissan',
            model: 'Patrol',
            year: 2021,
          ),
        ],
      );
      await _pump(tester, _flowApp(repository));
      final AppLocalizations l10n = _l10nOf(tester);

      await tester.tap(navItem(l10n.navInspections));
      await tester.pumpAndSettle();

      // One list with a status pill each, not two lists: an inspector's question
      // is "what does this car need", and that is a function of the row rather
      // than of which half of the list it fell into. The row names the car and
      // the city — the reference's own vocabulary for a listing — so the
      // fixtures are told apart by their car rather than by a reference number
      // the screen never prints.
      expect(find.text('Toyota FJ (2023)'), findsOneWidget);
      expect(find.text('Lexus ES350 (2022)'), findsOneWidget);
      expect(find.text(l10n.statusInProgress), findsOneWidget);
      expect(find.text(l10n.statusCompleted), findsOneWidget);
      expect(
        find.text('Nissan Patrol (2021)'),
        findsNothing,
        reason: 'anyone else\u2019s jobs are not an inspector\u2019s jobs',
      );
    });

    testWidgets('an empty jobs list says so and points nowhere in particular', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _flowApp(FakeInspectionRepository()));
      final AppLocalizations l10n = _l10nOf(tester);

      await tester.tap(navItem(l10n.navInspections));
      await tester.pumpAndSettle();

      expect(find.text(l10n.inspectionsEmpty), findsOneWidget);
      expect(find.text(l10n.inspectionsEmptyBody), findsOneWidget);
    });

    testWidgets('a claim appears on the jobs list even though it left the board', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(
            id: 'avail-1',
            referenceNo: 1005,
            make: 'Lexus',
            model: 'ES350',
          ),
        ],
      );
      // Started on the home shell, so the whole walk is the real one: the board's
      // `عرض كل` link, the listing, the detail. The market has no bottom nav of
      // its own, so a test that started there could not reach the jobs tab at all
      // without a back gesture the design does not draw.
      await _pump(tester, _flowApp(repository));
      final AppLocalizations l10n = _l10nOf(tester);

      await tester.tap(find.widgetWithText(TextButton, l10n.marketViewAll));
      await tester.pumpAndSettle();
      expect(find.byType(InspectorMarketPage), findsOneWidget);

      await tester.tap(find.text('Lexus ES350 (2019)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, l10n.actionAccept));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, l10n.actionAccept),
      ));
      await tester.pumpAndSettle();
      // Back out of the detail and off the market, onto the shell.
      await _systemBack(tester);
      await _systemBack(tester);

      await tester.tap(navItem(l10n.navInspections));
      await tester.pumpAndSettle();

      // The accepted request now lives on the jobs list, with its accepted
      // status, ready to be started.
      expect(find.text('Lexus ES350 (2019)'), findsOneWidget);
      expect(find.text(l10n.statusAccepted), findsOneWidget);
    });
  });

  group('InspectorHomePage · the wallet tab', () {
    testWidgets('earnings are completed jobs at the flat fee', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(
            id: 'done-1',
            referenceNo: 1001,
            inspectorId: 'inspector-1',
            status: InspectionStatus.completed,
            make: 'Lexus',
            model: 'ES350',
            year: 2022,
          ),
          buildRequest(
            id: 'done-2',
            referenceNo: 1002,
            inspectorId: 'inspector-1',
            status: InspectionStatus.completed,
            make: 'Nissan',
            model: 'Patrol',
            year: 2021,
          ),
          // Open work is counted separately and earns nothing yet.
          buildRequest(
            id: 'live-1',
            referenceNo: 1003,
            inspectorId: 'inspector-1',
            status: InspectionStatus.inProgress,
            make: 'Toyota',
            model: 'FJ',
            year: 2023,
          ),
        ],
      );
      await _pump(tester, _flowApp(repository));
      final AppLocalizations l10n = _l10nOf(tester);

      await tester.tap(navItem(l10n.navWallet));
      await tester.pumpAndSettle();

      expect(find.text(l10n.walletTotalEarnings), findsOneWidget);
      expect(find.text('ر.س 300'), findsOneWidget);
      expect(
        find.text(l10n.walletActiveJobs),
        findsOneWidget,
        reason: 'an in-progress job is active work, not an earning',
      );
      expect(find.text(l10n.walletCompletedJobs), findsOneWidget);
      expect(find.text('2 inspections'), findsOneWidget);
      expect(find.text('1 inspection'), findsOneWidget);
      // The completed rows sit behind the figure, so the total is checkable
      // rather than just asserted. The list names the car, not the reference:
      // an inspector reading a payout wants to know which inspections it covers.
      expect(find.text('Lexus ES350 (2022)'), findsOneWidget);
      expect(find.text('Nissan Patrol (2021)'), findsOneWidget);
      expect(
        find.text('Toyota FJ (2023)'),
        findsNothing,
        reason: 'an unfinished job is not behind the earnings figure',
      );
      // Each row quotes the fee it contributed, so the arithmetic is visible.
      expect(find.text('ر.س 150'), findsNWidgets(2));
    });

    testWidgets('an inspector with no completed work earns nothing, and is told so', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _flowApp(
          FakeInspectionRepository(
            requests: <InspectionRequest>[
              buildRequest(
                id: 'live-1',
                referenceNo: 1003,
                inspectorId: 'inspector-1',
                status: InspectionStatus.accepted,
              ),
            ],
          ),
        ),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      await tester.tap(navItem(l10n.navWallet));
      await tester.pumpAndSettle();

      // Zero is printed, not hidden: an inspector who has just finished their
      // first job needs to see the figure, and the figure is zero.
      expect(find.text('ر.س 0'), findsOneWidget);
      expect(find.text(l10n.walletEmpty), findsOneWidget);
      expect(find.text(l10n.walletEmptyBody), findsOneWidget);
    });
  });

  group('InspectorHomePage · the profile tab', () {
    testWidgets('shows the facts the buyer sees, with the rating', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _app(FakeInspectionRepository(), child: const InspectorHomePage()));
      final AppLocalizations l10n = _l10nOf(tester);

      await tester.tap(navItem(l10n.navProfileTab));
      await tester.pumpAndSettle();

      expect(find.text('Karim Adel'), findsOneWidget);
      expect(find.text(l10n.roleInspector), findsOneWidget);
      expect(find.text('Dammam'), findsWidgets);
      // Two decimals: the design draws no rating anywhere, and a five-star scale
      // that rounds 4.45 to 4.5 looks like it is rounding the work away.
      expect(find.text('4.50'), findsOneWidget);
      expect(find.text('4.5'), findsNothing);
      expect(find.text(l10n.actionSignOut), findsOneWidget);
    });

    testWidgets('changing the service city updates the profile and the board', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository auth = FakeAuthRepository(
        profile: _signedInInspector,
        userId: _signedInInspector.id,
      );
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(
            id: 'avail-1',
            referenceNo: 1005,
            make: 'Lexus',
            model: 'ES350',
          ),
        ],
      );
      await _pump(
        tester,
        _app(
          repository,
          child: const InspectorMarketPage(),
          authRepository: auth,
        ),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      // The board is scoped to the profile's city before anything is edited.
      expect(marketHeaderCity(l10n, 'Dammam'), findsOneWidget);

      await _pump(
        tester,
        _app(
          repository,
          child: const InspectorHomePage(),
          authRepository: auth,
        ),
      );
      await tester.tap(navItem(l10n.navProfileTab));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.profileEditCity));
      await tester.pumpAndSettle();

      // A sheet, not a dialog: the profile editor reuses the same city sheet the
      // create form's field opens, so there is one control for a city in the app
      // rather than two that behave differently. The sheet shows the *list*,
      // not a field — one tap from the profile row to the city.
      expect(find.text('Jeddah'), findsWidgets);
      await tester.tap(find.text('Jeddah').last);
      await tester.pumpAndSettle();

      expect(auth.updatedCities, <String>['Jeddah']);
      expect(find.text(l10n.profileCityUpdated), findsOneWidget);
      // The profile row now shows the new canonical city.
      expect(find.text('Jeddah'), findsWidgets);

      // The board header follows the new service city, which is the whole point:
      // RLS compares each request's city against this column, so a profile that
      // is not updated is an inspector with a permanently empty board.
      await _pump(
        tester,
        _app(
          repository,
          child: const InspectorMarketPage(),
          authRepository: auth,
        ),
      );
      expect(marketHeaderCity(l10n, 'Jeddah'), findsOneWidget);
      expect(marketHeaderCity(l10n, 'Dammam'), findsNothing);
    });

    testWidgets('an inspector without ratings is told so', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        ProviderScope(
          overrides: [
            inspectionRepositoryProvider.overrideWithValue(
              FakeInspectionRepository(),
            ),
            authControllerProvider.overrideWith(_UnratedAuthController.new),
            localeProvider.overrideWithValue(const Locale('en')),
          ],
          child: MaterialApp(
            home: const InspectorHomePage(),
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      await tester.tap(navItem(l10n.navProfileTab));
      await tester.pumpAndSettle();

      expect(find.text(l10n.detailNoRatingsYet), findsOneWidget);
    });
  });
}

/// The localizations for whatever is on screen, read from a page context (the
/// `MaterialApp`'s own context has none — see the RTL test file).
AppLocalizations _l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first));