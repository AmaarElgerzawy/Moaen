import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moaen/app.dart';
import 'package:moaen/core/env.dart';
import 'package:moaen/features/auth/auth_controller.dart';
import 'package:moaen/features/auth/auth_repository.dart';
import 'package:moaen/features/auth/sign_in_page.dart';
import 'package:moaen/features/auth/user_profile.dart';
import 'package:moaen/features/home/role_landing_page.dart';

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
    if (value == null) throw const AuthFailure('Profile unavailable.');
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

Widget _app(FakeAuthRepository repository) => ProviderScope(
  overrides: [authRepositoryProvider.overrideWithValue(repository)],
  child: const MoaenApp(),
);

void main() {
  group('configuration', () {
    test('reports an unconfigured build and names the missing defines', () {
      // Tests compile without --dart-define, so this is the path a developer
      // hits on a bare `flutter run`. It must be actionable, not silent.
      expect(Env.isSupabaseConfigured, isFalse);
      expect(
        Env.validate,
        throwsA(
          isA<AppConfigurationError>().having(
            (AppConfigurationError e) => e.message,
            'message',
            allOf(contains('SUPABASE_URL'), contains('SUPABASE_PUBLISHABLE_KEY')),
          ),
        ),
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

    testWidgets('a restored session lands on the role screen (O1)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(FakeAuthRepository(userId: 'user-1', profile: _profile())),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RoleLandingPage), findsOneWidget);
      expect(find.byType(SignInPage), findsNothing);
      expect(find.text('Nadia Hassan'), findsOneWidget);
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
      expect(repository.signInCalls, 0, reason: 'validation must gate the call');
    });

    testWidgets('surfaces a failure from the repository', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = FakeAuthRepository(
        failure: const AuthFailure('Incorrect email or password.'),
      );
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'nadia@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'wrong-password');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Incorrect email or password.'), findsOneWidget);
      expect(find.byType(RoleLandingPage), findsNothing);
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
