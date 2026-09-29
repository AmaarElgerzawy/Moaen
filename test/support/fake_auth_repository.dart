import 'package:moaen/features/auth/auth_repository.dart';
import 'package:moaen/features/auth/user_profile.dart';

import 'test_client.dart';

/// An [AuthRepository] with no network behind it, for the profile editor.
///
/// The real repository is a concrete class over [SupabaseClient], so this fakes
/// it by subclassing and overriding the members the profile tab exercises. The
/// client passed to `super` is never called (constructing it performs no I/O,
/// see `test_client.dart`); it exists only to satisfy the constructor.
class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository({this.profile, this.userId = 'user-1'})
    : super(createTestClient());

  /// The profile [loadProfile] returns, and [signIn]/[signUp] succeed with.
  final UserProfile? profile;

  /// The identity [currentUserId] reports.
  final String? userId;

  int profileLoads = 0;

  /// Every city handed to [updateCity], in order — the assertion surface for
  /// the "change service city" flow.
  final List<String> updatedCities = <String>[];

  @override
  String? get currentUserId => userId;

  @override
  Future<UserProfile> loadProfile(String userId) async {
    profileLoads++;
    return profile ??
        UserProfile(
          id: userId,
          fullName: '',
          email: '',
          role: UserRole.client,
        );
  }

  @override
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    final UserProfile? existing = profile;
    if (existing == null) {
      throw const AuthFailure(AuthFailureReason.invalidCredentials);
    }
    return existing;
  }

  @override
  Future<UserProfile> signUp({
    required String email,
    required String password,
    required String fullName,
    required UserRole role,
    String? phone,
    String? city,
  }) async {
    final UserProfile? existing = profile;
    if (existing == null) {
      throw const AuthFailure(AuthFailureReason.signupsDisabled);
    }
    return existing;
  }

  @override
  Future<void> updateCity(String city) async {
    updatedCities.add(city);
  }

  @override
  Future<void> signOut() async {}
}