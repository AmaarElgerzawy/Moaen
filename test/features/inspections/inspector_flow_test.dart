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
import 'package:moaen/features/cities/presentation/city_picker.dart';
import 'package:moaen/features/inspections/application/inspection_controller.dart';
// Not transitive from the fake: Dart imports are per-library, so a test that
// constructs an `InspectionFailure` has to name where it comes from.
import 'package:moaen/features/inspections/data/inspection_repository.dart';
import 'package:moaen/features/inspections/domain/inspection_request.dart';
import 'package:moaen/features/inspections/presentation/inspector_home_page.dart';
import 'package:moaen/features/inspections/presentation/inspector_job_detail_page.dart';
import 'package:moaen/l10n/gen/app_localizations.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_cities.dart';
import '../../support/fake_inspection_repository.dart';

/// Widget tests for the inspector side: the job board, the jobs list, the
/// profile tab and the request detail with its three status actions.
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
  locationCity: 'Cairo',
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
  locationCity: 'Cairo',
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

/// The home and the detail under one router, so tap-through navigation between
/// them is exercised rather than stubbed.
Widget _flowApp(FakeInspectionRepository repository) => ProviderScope(
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
        GoRoute(path: '/', builder: (_, _) => const InspectorHomePage()),
        GoRoute(
          path: '/inspector/jobs/:id',
          name: 'inspectorJobDetail',
          builder: (_, GoRouterState state) =>
              InspectorJobDetailPage(id: state.pathParameters['id'] ?? ''),
        ),
      ],
    ),
  ),
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
  group('InspectorHomePage · job board', () {
    testWidgets('shows only requests still waiting to be claimed', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(id: 'avail-1', referenceNo: 1005),
          buildRequest(id: 'avail-2', referenceNo: 1004),
          buildRequest(
            id: 'mine-1',
            referenceNo: 1003,
            inspectorId: 'inspector-1',
            status: InspectionStatus.accepted,
          ),
        ],
      );
      await _pump(tester, _app(repository, child: const InspectorHomePage()));
      final AppLocalizations l10n = _l10nOf(tester);

      expect(find.text('MN-1005'), findsOneWidget);
      expect(find.text('MN-1004'), findsOneWidget);
      expect(
        find.text('MN-1003'),
        findsNothing,
        reason: 'a claimed request is not available to be claimed',
      );
      expect(find.text(l10n.boardTitle('Cairo')), findsOneWidget);
    });

    testWidgets('an empty board says so and names the city', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _app(FakeInspectionRepository(), child: const InspectorHomePage()));
      final AppLocalizations l10n = _l10nOf(tester);

      expect(find.text(l10n.boardEmptyTitle), findsOneWidget);
      expect(find.text(l10n.boardEmptyBody('Cairo')), findsOneWidget);
    });

    testWidgets('a failed board load is retryable', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(id: 'avail-1', referenceNo: 1005),
        ],
        failure: const InspectionFailure('Could not load the job board.'),
      );
      await _pump(tester, _app(repository, child: const InspectorHomePage()));
      final AppLocalizations l10n = _l10nOf(tester);

      expect(find.text(l10n.boardLoadError), findsOneWidget);
      expect(find.text('MN-1005'), findsNothing);

      repository.failure = null;
      await tester.tap(find.widgetWithText(FilledButton, l10n.actionRetry));
      await tester.pumpAndSettle();

      expect(find.text('MN-1005'), findsOneWidget);
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
        requests: <InspectionRequest>[buildRequest(id: 'avail-1', referenceNo: 1005)],
      );
      await _pump(tester, _flowApp(repository));
      final AppLocalizations l10n = _l10nOf(tester);

      // Through the board: tap the row, then accept.
      await tester.tap(find.text('MN-1005'));
      await tester.pumpAndSettle();

      expect(find.byType(InspectorJobDetailPage), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, l10n.actionAccept));
      await tester.pumpAndSettle();

      // The page action and the dialog action share the same label, so the
      // dialog's button is found inside the dialog, not on screen-wide text.
      expect(find.text(l10n.acceptConfirmTitle), findsOneWidget);
      expect(find.text(l10n.acceptConfirmBody('Cairo')), findsOneWidget);
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

      // Back on the board, the claimed request is gone.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('MN-1005'), findsNothing);
      expect(find.text(l10n.boardEmptyTitle), findsOneWidget);
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
            notes: 'The rear bumper is resprayed.',
          ),
        ],
      );
      await _pump(
        tester,
        _app(repository, child: const InspectorJobDetailPage(id: 'mine-1')),
      );
      final AppLocalizations l10n = _l10nOf(tester);

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
      // A settled job offers no action, and says so.
      expect(find.widgetWithText(FilledButton, l10n.actionComplete), findsNothing);
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

  group('InspectorHomePage · my jobs', () {
    testWidgets('separates open work from settled work', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(
            id: 'open-1',
            referenceNo: 1003,
            inspectorId: 'inspector-1',
            status: InspectionStatus.inProgress,
          ),
          buildRequest(
            id: 'done-1',
            referenceNo: 1002,
            inspectorId: 'inspector-1',
            status: InspectionStatus.completed,
          ),
          // Another inspector's job must not appear at all.
          buildRequest(
            id: 'theirs-1',
            referenceNo: 1001,
            inspectorId: 'inspector-2',
            status: InspectionStatus.accepted,
          ),
        ],
      );
      await _pump(tester, _flowApp(repository));
      final AppLocalizations l10n = _l10nOf(tester);

      await tester.tap(find.text(l10n.navMyJobs));
      await tester.pumpAndSettle();

      expect(find.text(l10n.myRequestsOpen), findsOneWidget);
      expect(find.text(l10n.myRequestsSettled), findsOneWidget);
      expect(find.text('MN-1003'), findsOneWidget);
      expect(find.text('MN-1002'), findsOneWidget);
      expect(
        find.text('MN-1001'),
        findsNothing,
        reason: 'anyone else\u2019s jobs are not an inspector\u2019s jobs',
      );
    });

    testWidgets('an empty jobs list says so and points nowhere in particular', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _flowApp(FakeInspectionRepository()));
      final AppLocalizations l10n = _l10nOf(tester);

      await tester.tap(find.text(l10n.navMyJobs));
      await tester.pumpAndSettle();

      expect(find.text(l10n.jobsEmpty), findsOneWidget);
      expect(find.text(l10n.myRequestsOpen), findsNothing);
    });

    testWidgets('a claim appears on my jobs even though it left the board', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[buildRequest(id: 'avail-1', referenceNo: 1005)],
      );
      await _pump(tester, _flowApp(repository));
      final AppLocalizations l10n = _l10nOf(tester);

      await tester.tap(find.text('MN-1005'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, l10n.actionAccept));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, l10n.actionAccept),
      ));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.navMyJobs));
      await tester.pumpAndSettle();

      // The accepted request now lives on the jobs list, with its accepted
      // status, ready to be started.
      expect(find.text('MN-1005'), findsOneWidget);
      expect(find.text(l10n.statusAccepted), findsOneWidget);
    });
  });

  group('InspectorHomePage · profile', () {
    testWidgets('shows the facts the buyer sees, with the rating', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _app(FakeInspectionRepository(), child: const InspectorHomePage()));
      final AppLocalizations l10n = _l10nOf(tester);

      await tester.tap(find.text(l10n.navProfile));
      await tester.pumpAndSettle();

      expect(find.text('Karim Adel'), findsOneWidget);
      expect(find.text(l10n.roleInspector), findsOneWidget);
      expect(find.text('Cairo'), findsWidgets);
      expect(find.text('4.50'), findsOneWidget);
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
          buildRequest(id: 'avail-1', referenceNo: 1005, city: 'Cairo'),
        ],
      );
      await _pump(
        tester,
        _app(
          repository,
          child: const InspectorHomePage(),
          authRepository: auth,
        ),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      // The board is scoped to the profile's city before anything is edited.
      expect(find.text(l10n.boardTitle('Cairo')), findsOneWidget);

      await tester.tap(find.text(l10n.navProfile));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.profileEditCity));
      await tester.pumpAndSettle();

      // Open the picker sheet inside the dialog, then pick a different city.
      await tester.tap(find.byType(CityPicker).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Giza').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, l10n.actionSave));
      await tester.pumpAndSettle();

      expect(auth.updatedCities, <String>['Giza']);
      expect(find.text(l10n.profileCityUpdated), findsOneWidget);
      // The profile row now shows the new canonical city.
      expect(find.text('Giza'), findsWidgets);

      // The board header follows the new service city.
      await tester.tap(find.text(l10n.navJobBoard));
      await tester.pumpAndSettle();
      expect(find.text(l10n.boardTitle('Giza')), findsOneWidget);
      expect(find.text(l10n.boardTitle('Cairo')), findsNothing);
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

      await tester.tap(find.text(l10n.navProfile));
      await tester.pumpAndSettle();

      expect(find.text(l10n.detailNoRatingsYet), findsOneWidget);
    });
  });
}

/// The localizations for whatever is on screen, read from a page context (the
/// `MaterialApp`'s own context has none — see the RTL test file).
AppLocalizations _l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first));