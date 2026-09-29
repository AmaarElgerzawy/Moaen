import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moaen/app.dart';
import 'package:moaen/core/env.dart';
import 'package:moaen/core/localization/locale_provider.dart';
import 'package:moaen/features/auth/auth_controller.dart';
import 'package:moaen/features/auth/auth_repository.dart';
import 'package:moaen/features/auth/sign_in_page.dart';
import 'package:moaen/features/auth/user_profile.dart';
import 'package:moaen/features/home/role_landing_page.dart';
import 'package:moaen/features/inspections/application/inspection_controller.dart';
import 'package:moaen/features/inspections/domain/inspection_request.dart';
import 'package:moaen/features/inspections/presentation/client_dashboard_page.dart';
import 'package:moaen/features/inspections/presentation/inspector_home_page.dart';

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

UserProfile _profile({
  UserRole role = UserRole.client,
  String? city,
  String name = 'Nadia Hassan',
}) => UserProfile(
  id: 'user-1',
  fullName: name,
  email: 'nadia@example.com',
  role: role,
  locationCity: city,
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
  ],
  child: const MoaenApp(),
);

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
            profile: _profile(role: UserRole.inspector, city: 'Cairo'),
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
      await tester.pumpWidget(
        _app(FakeAuthRepository(userId: 'user-1', profile: _profile())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Sign out'));
      await tester.pumpAndSettle();

      expect(find.byType(SignInPage), findsOneWidget);
      expect(find.byType(RoleLandingPage), findsNothing);
    });

    testWidgets('an inspector sees their service city, a buyer does not', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          FakeAuthRepository(
            userId: 'user-1',
            profile: _profile(role: UserRole.inspector, city: 'Alexandria'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The board greets with the service city even when it is empty.
      expect(find.textContaining('Alexandria'), findsOneWidget);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      // The profile tab, like the old role screen, shows the role and the
      // service city the buyer-facing side of the app shows when hiring.
      expect(find.text('Inspector'), findsOneWidget);
      expect(find.text('Alexandria'), findsOneWidget);
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
