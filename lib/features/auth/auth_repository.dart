import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/logging/app_logger.dart';
import 'user_profile.dart';

/// A failure that is safe to show to the user.
///
/// [AuthException.message] from the server is not shown verbatim: it can carry
/// internal detail, and in the case of a disabled sign-up it reads like a bug
/// rather than a product state. The original is logged, not displayed.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// All authentication and profile reads go through here.
///
/// The controller layer above deals in [UserProfile] and [AuthFailure] only, so
/// a widget test can substitute this class without a network.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  /// The id of the restored session at startup, or null on a cold signed-out
  /// launch.
  ///
  /// Deliberately the id rather than the whole `Session`: the caller only ever
  /// needs to know who is signed in, and returning a narrower type keeps the
  /// transport types out of the controller and out of its tests.
  String? get currentUserId => _client.auth.currentSession?.user.id;

  /// Reads the caller's own `public.users` row.
  ///
  /// RLS restricts this to the caller's own record, so there is no
  /// user-supplied id to validate here: the row is looked up by the session's
  /// own id and the database decides what it is allowed to return.
  Future<UserProfile> loadProfile(String userId) async {
    final Map<String, dynamic> row =
        await _client.from('users').select().eq('id', userId).single();
    return UserProfile.fromRow(row);
  }

  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final AuthResponse response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      final User? user = response.user;
      if (user == null) {
        throw const AuthFailure('Sign-in succeeded but returned no account.');
      }
      return await loadProfile(user.id);
    } on AuthException catch (error, stackTrace) {
      AppLogger.instance.error('sign-in failed', error, stackTrace, {'email': email});
      throw AuthFailure(_messageFor(error));
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('profile load failed', error, stackTrace);
      throw const AuthFailure(
        'Signed in, but your profile could not be loaded. Please try again.',
      );
    }
  }

  /// Registers a new account.
  ///
  /// The requested role travels as Auth metadata, which is what the
  /// `handle_new_user` trigger reads. The database whitelists it to
  /// client|inspector, so passing `admin` here achieves nothing but a
  /// harmless no-op; the parameter is typed to the two assignable roles so the
  /// intent is visible at the call site.
  Future<UserProfile> signUp({
    required String email,
    required String password,
    required String fullName,
    required UserRole role,
    String? phone,
    String? city,
  }) async {
    if (role == UserRole.admin) {
      throw const AuthFailure('Administrator accounts cannot be self-registered.');
    }

    try {
      final AuthResponse response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: <String, dynamic>{
          'full_name': fullName.trim(),
          'role': role.name,
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
          if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
        },
      );

      final User? user = response.user;
      if (user == null) {
        throw const AuthFailure('Registration failed. Please try again.');
      }
      if (response.session == null) {
        throw const AuthFailure(
          'Account created. Check your email to confirm the address, '
          'then sign in.',
        );
      }
      return await loadProfile(user.id);
    } on AuthException catch (error, stackTrace) {
      AppLogger.instance.error('sign-up failed', error, stackTrace, {'email': email});
      throw AuthFailure(_messageFor(error));
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on AuthException catch (error, stackTrace) {
      AppLogger.instance.error('sign-out failed', error, stackTrace);
      throw const AuthFailure('Could not sign out. Please try again.');
    }
  }

  /// Maps a server auth error onto something a person can act on.
  String _messageFor(AuthException error) {
    AppLogger.instance.debug('auth error detail', {'raw': error.message});

    final String detail = error.message.toLowerCase();
    if (detail.contains('invalid login credentials')) {
      return 'Incorrect email or password.';
    }
    if (detail.contains('email not confirmed')) {
      return 'Confirm your email address before signing in.';
    }
    if (detail.contains('already registered') ||
        detail.contains('already been registered')) {
      return 'An account with this email already exists.';
    }
    if (detail.contains('signups not allowed')) {
      return 'Registration is currently closed.';
    }
    if (detail.contains('rate limit')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    return 'Something went wrong while signing in. Please try again.';
  }
}
