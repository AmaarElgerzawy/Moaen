import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moaen/app.dart';
import 'package:moaen/core/env.dart';
import 'package:moaen/core/localization/locale_provider.dart';
import 'package:moaen/core/router/app_router.dart';
import 'package:moaen/core/theme/app_theme.dart';
import 'package:moaen/features/admin/presentation/admin_home_page.dart';
import 'package:moaen/features/auth/auth_controller.dart';
import 'package:moaen/features/auth/auth_repository.dart';
import 'package:moaen/features/auth/sign_in_page.dart';
import 'package:moaen/features/auth/user_profile.dart';
import 'package:moaen/features/home/role_landing_page.dart';
import 'package:moaen/features/inspections/application/inspection_controller.dart';
import 'package:moaen/features/inspections/domain/inspection_request.dart';
import 'package:moaen/features/inspections/presentation/client_dashboard_page.dart';
import 'package:moaen/features/inspections/presentation/inspector_home_page.dart';
import 'package:moaen/features/inspections/presentation/widgets/design_widgets.dart';
import 'package:moaen/features/cities/application/city_controller.dart';
import 'package:moaen/l10n/gen/app_localizations.dart';

import '../../support/fake_cities.dart';
import '../../support/test_client.dart';

/// An [AuthRepository] with no network behind it.
///
/// The real repository is a concrete class over [SupabaseClient], so the fake
/// subclasses it and overrides only the four members the app actually uses. The
/// client it passes to `super` is never called: it exists only to satisfy the
/// constructor, and constructing one performs no I/O.
class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository({this.userId, this.profile, this.failure})
    : super(createTestClient());

  String? userId;
  final UserProfile? profile;
  final AuthFailure? failure;

  int signInCalls = 0;
  int signOutCalls = 0;
  int profileLoads = 0;

  @override
  String? get currentUserId => userId;

  @override
  Future<UserProfile> loadProfile(String userId) async {
    profileLoads++;
    final UserProfile? value = profile;
    if (value == null) {
      throw const AuthFailure(AuthFailureReason.profileUnavailable);
    }
    return value;
  }

  @override
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    signInCalls++;
    final AuthFailure? error = failure;
    if (error != null) throw error;
    userId = profile?.id;
    return loadProfile(userId!);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    userId = null;
  }
}

/// A profile for the routing tests.
///
/// Inspectors default to [approved] true because the access gate sends an
/// unapproved one to `/restricted` before any role rule runs — which is the point of
/// the gate, and is asserted in `access_restricted_test.dart`. A routing test that
/// wanted to check "an inspector lands on the inspector home" would otherwise be
/// testing the gate, and would keep passing if the *dispatch* broke and the gate
/// quietly started letting everyone through.
UserProfile _profile({
  UserRole role = UserRole.client,
  String? city,
  String name = 'Nadia Hassan',
  bool approved = true,
  bool blocked = false,
}) => UserProfile(
  id: 'user-1',
  fullName: name,
  email: 'nadia@example.com',
  role: role,
  locationCity: city,
  isApproved: approved,
  isBlocked: blocked,
);

/// Renders the real [MoaenApp] in English.
///
/// These tests cover the routing guard and form validation, not translation, so
/// they assert against English finders. The app's own default is Arabic (D7),
/// overridden here so a wording change in `app_ar.arb` cannot break a test about
/// whether a session lands on the right screen. The Arabic and RTL behaviour
/// that the override would otherwise hide is covered in
/// `test/core/localization_test.dart`.
Widget _app(FakeAuthRepository repository) => ProviderScope(
  overrides: [
    authRepositoryProvider.overrideWithValue(repository),
    localeProvider.overrideWithValue(const Locale('en')),
    // A client now lands on the dashboard, which reads the buyer's open
    // request. Overridden rather than allowed to reach the fake Supabase
    // client, which would attempt a real request and leave an unresolved
    // future in the test. Null is the honest "no active request" state.
    dashboardRequestProvider.overrideWith((Ref ref) async => null),
    // An inspector lands on the inspector home, which reads the board and the
    // inspector's jobs. Both are straightforward reads that would otherwise
    // attempt a real request, so they are overridden with the honest empty
    // states.
    jobBoardProvider.overrideWith((Ref ref) async => const <InspectionRequest>[]),
    myJobsProvider.overrideWith((Ref ref) async => const <InspectionRequest>[]),
    // The register form's city field is the canonical-city picker, which reads
    // the city list; overridden so the picker never reaches the fake client.
    citiesProvider.overrideWith((Ref ref) async => testCities),
  ],
  child: const MoaenApp(),
);

/// A destination in the shell's bottom bar.
///
/// Scoped to the bar because the open tab's label is also its screen's heading,
/// so a bare `find.text` would match two widgets and `tap` would refuse.
Finder _navItem(String label) => find.descendant(
  of: find.byType(AppBottomNav),
  matching: find.text(label),
);

/// What [_pumpRouter] hands back, so a test can navigate the *real* router.
class RouterHarness {
  const RouterHarness(this.router);

  final GoRouter router;
}

/// Mounts the app's real [routerProvider] over a fake session.
///
/// For the redirect rules that [MoaenApp] cannot reach on its own: they are about
/// where a navigation is *refused*, so a test has to ask for a route and be turned
/// away. Pumping the real provider rather than building a second router is the whole
/// point — a copy of the redirect would be a copy of the rule, and a rule with two
/// copies is a rule with two answers.
Future<RouterHarness> _pumpRouter(
  WidgetTester tester,
  FakeAuthRepository repository,
) async {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      localeProvider.overrideWithValue(const Locale('en')),
      dashboardRequestProvider.overrideWith((Ref ref) async => null),
      jobBoardProvider.overrideWith((Ref ref) async => const <InspectionRequest>[]),
      myJobsProvider.overrideWith((Ref ref) async => const <InspectionRequest>[]),
      citiesProvider.overrideWith((Ref ref) async => testCities),
    ],
  );
  addTearDown(container.dispose);

  late GoRouter router;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (BuildContext context, WidgetRef ref, _) {
          router = ref.watch(routerProvider);
          return MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();

  addTearDown(router.dispose);
  return RouterHarness(router);
}

void main() {
  group('configuration', () {
    // A debug build falls back to the development project, so a bare
    // `flutter run` is configured. These tests run in debug, which means they
    // can never observe a release build's missing-credentials path directly;
    // `validateCredentials` takes the values as parameters precisely so that
    // path stays reachable from here.
    test('a debug build is configured without any --dart-define', () {
      expect(Env.isSupabaseConfigured, isTrue);
      expect(Env.isUsingDevDefaults, isTrue);
      // Must not throw, or the app would refuse to start on the emulator.
      expect(Env.validate, returnsNormally);
    });

    test('a missing url is reported with an actionable message', () {
      expect(
        () => Env.validateCredentials('', 'sb_publishable_x'),
        throwsA(
          isA<AppConfigurationError>().having(
            (AppConfigurationError e) => e.message,
            'message',
            allOf(
              contains('SUPABASE_URL'),
              contains('SUPABASE_PUBLISHABLE_KEY'),
            ),
          ),
        ),
      );
    });

    test('a missing key is reported with an actionable message', () {
      expect(
        () => Env.validateCredentials('https://x.supabase.co', ''),
        throwsA(isA<AppConfigurationError>()),
      );
    });

    test('a url that is not absolute is rejected', () {
      expect(
        () => Env.validateCredentials('ybglobvcqgkfclvkjkri.supabase.co', 'k'),
        throwsA(
          isA<AppConfigurationError>().having(
            (AppConfigurationError e) => e.message,
            'message',
            contains('absolute http(s) URL'),
          ),
        ),
      );
    });

    test('a non-http scheme is rejected', () {
      expect(
        () => Env.validateCredentials('ftp://x.supabase.co', 'k'),
        throwsA(
          isA<AppConfigurationError>().having(
            (AppConfigurationError e) => e.message,
            'message',
            contains('must use http or https'),
          ),
        ),
      );
    });

    test('a valid release configuration passes', () {
      expect(
        () => Env.validateCredentials(
          'https://ybglobvcqgkfclvkjkri.supabase.co',
          'sb_publishable_qGZ3U2FHarEMD9Mtsg8mHg_eYsNswOp',
        ),
        returnsNormally,
      );
    });
  });

  group('routing guard', () {
    testWidgets('a signed-out launch lands on the sign-in screen', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_app(FakeAuthRepository()));
      await tester.pumpAndSettle();

      expect(find.byType(SignInPage), findsOneWidget);
      expect(find.byType(RoleLandingPage), findsNothing);
    });

    testWidgets('a restored client session lands on the dashboard (O1)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(FakeAuthRepository(userId: 'user-1', profile: _profile())),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ClientDashboardPage), findsOneWidget);
      expect(find.byType(RoleLandingPage), findsNothing);
      expect(find.byType(SignInPage), findsNothing);
    });

    testWidgets('a restored inspector session lands on the inspector home (O1)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          FakeAuthRepository(
            userId: 'user-2',
            profile: _profile(role: UserRole.inspector, city: 'Dammam'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The inspector half of O1: inspectors now have a real home of their own
      // (board, jobs, profile), so the role screen is no longer their
      // destination. The client's is not either, and a test that asserted one
      // destination for both roles would have passed right up until the
      // dashboard existed.
      expect(find.byType(InspectorHomePage), findsOneWidget);
      expect(find.byType(ClientDashboardPage), findsNothing);
      expect(find.byType(RoleLandingPage), findsNothing);
      expect(find.byType(SignInPage), findsNothing);
    });

    testWidgets('signing out returns to the sign-in screen', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = FakeAuthRepository(
        userId: 'user-1',
        profile: _profile(),
      );
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      // The account tab, not the header square. Sign-out is where the design puts
      // it and it is the one action on the account screen that ends the session,
      // so a tap in the header that signs you out is a trap in the one place a
      // finger goes by habit.
      await tester.tap(_navItem('Account'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(repository.signOutCalls, 1);
      expect(find.byType(SignInPage), findsOneWidget);
      expect(find.byType(RoleLandingPage), findsNothing);
    });

    testWidgets("an inspector's service city is on the profile tab", (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          FakeAuthRepository(
            userId: 'user-1',
            profile: _profile(role: UserRole.inspector, city: 'Riyadh'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Not on the task board: Screen 4 has no service-city line, and an
      // inspector's own city is not part of a summary of somebody else's job.
      expect(find.textContaining('Riyadh'), findsNothing);

      await tester.tap(_navItem('Profile'));
      await tester.pumpAndSettle();

      // On the profile tab, like the old role screen, beside the role — because
      // this is where an inspector has to come to correct it. RLS scopes the
      // board by this column, so a wrong city is an empty board.
      expect(find.text('Inspector'), findsOneWidget);
      expect(find.text('Riyadh'), findsOneWidget);
    });

    testWidgets('an admin lands on the panel, not on either role home (O1)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          FakeAuthRepository(
            userId: 'admin-1',
            profile: _profile(role: UserRole.admin, name: 'Khalid Admin'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AdminHomePage), findsOneWidget);
      expect(find.byType(RoleLandingPage), findsNothing);
      expect(find.byType(InspectorHomePage), findsNothing);
      expect(find.byType(ClientDashboardPage), findsNothing);
    });

    testWidgets('a buyer who asks for the panel is sent home instead', (
      WidgetTester tester,
    ) async {
      // The gate has to be asserted for the role that *cannot* use the panel, not
      // only for the one that can. Without it a client who had once been an admin —
      // or who simply guessed the URL — lands on a screen of five empty tabs and a
      // banner of permission errors, which is the exact outcome the gate exists to
      // prevent.
      //
      // Driven through the real [routerProvider] rather than a router built here. A
      // copy of the redirect in the test would be a second copy of the rule, and
      // the failure this guards against is precisely the two copies drifting.
      final RouterHarness harness = await _pumpRouter(
        tester,
        FakeAuthRepository(userId: 'user-1', profile: _profile()),
      );

      // The client has to have landed somewhere first: `go` on a router whose first
      // build has not happened yet resolves against an empty configuration, and the
      // assertion below would pass for the wrong reason.
      expect(find.byType(ClientDashboardPage), findsOneWidget);

      harness.router.go(AppRoutes.admin);
      await tester.pumpAndSettle();

      // Unreachable by construction — the point is that the navigation was
      // refused, not that a panel rendered something.
      expect(find.byType(AdminHomePage), findsNothing);
      expect(
        harness.router.routerDelegate.currentConfiguration.uri.path,
        AppRoutes.dashboard,
      );
    });

    testWidgets('a suspended inspector is kept off the board by the access gate', (
      WidgetTester tester,
    ) async {
      // The gate runs *ahead* of the role dispatch, so a blocked inspector asking for
      // their own home lands on the restricted screen rather than on a board the
      // database is about to refuse to fill. Asserting the landing place and not just
      // "not the board" is what pins the ordering: a gate that ran last would pass
      // the weaker assertion and fail this one.
      final RouterHarness harness = await _pumpRouter(
        tester,
        FakeAuthRepository(
          userId: 'user-2',
          profile: _profile(
            role: UserRole.inspector,
            city: 'Dammam',
            blocked: true,
          ),
        ),
      );

      harness.router.go(AppRoutes.inspector);
      await tester.pumpAndSettle();

      expect(find.byType(InspectorHomePage), findsNothing);
      expect(
        harness.router.routerDelegate.currentConfiguration.uri.path,
        AppRoutes.restricted,
      );
    });
  });

  group('sign-in form', () {
    testWidgets('rejects a malformed email before calling the backend', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = FakeAuthRepository();
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(
        repository.signInCalls,
        0,
        reason: 'validation must gate the call',
      );
    });

    testWidgets('surfaces a failure from the repository', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = FakeAuthRepository(
        failure: const AuthFailure(AuthFailureReason.invalidCredentials),
      );
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        'nadia@example.com',
      );
      await tester.enterText(find.byType(TextFormField).last, 'wrong-password');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Incorrect email or password.'), findsOneWidget);
      expect(find.byType(RoleLandingPage), findsNothing);
    });

    // The failure that was hardest to diagnose. GoTrue answers a disabled
    // provider with 400 "Email signups are disabled" on sign-up and 422 "Email
    // logins are disabled" on the password grant, and before this reason existed
    // both fell through to the generic sentence — so an operator error reached
    // the user as "Something went wrong. Please try again." while the whole app
    // was unusable. It now has its own sentence and its own log line.
    testWidgets('a disabled auth provider says so instead of "try again"', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = FakeAuthRepository(
        failure: const AuthFailure(AuthFailureReason.providerDisabled),
      );
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        'nadia@example.com',
      );
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(
        find.text('Signing in is unavailable right now. Please try again later.'),
        findsOneWidget,
      );
      expect(
        find.text('Something went wrong. Please try again.'),
        findsNothing,
        reason: 'a configuration fault must not read as a transient error',
      );
    });

    // The server's own wording is the one thing that identifies the fault
    // precisely, and it must not be rendered. It is kept on the failure for the
    // log.
    testWidgets('the server detail is never shown to the user', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = FakeAuthRepository(
        failure: const AuthFailure(
          AuthFailureReason.providerDisabled,
          detail: 'Email logins are disabled',
        ),
      );
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        'nadia@example.com',
      );
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Email logins are disabled'), findsNothing);
    });

    testWidgets('reaching the register form reveals the role and city fields', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_app(FakeAuthRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Create an account'));
      await tester.pumpAndSettle();

      expect(find.text('Full name'), findsOneWidget);
      expect(find.text('I inspect'), findsOneWidget);
      expect(
        find.text('Service city'),
        findsNothing,
        reason: 'a buyer has no service city',
      );

      await tester.tap(find.text('I inspect'));
      await tester.pumpAndSettle();

      expect(find.text('Service city'), findsOneWidget);
    });
  });
}
