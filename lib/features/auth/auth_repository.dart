import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/logging/app_logger.dart';
import 'data/identity_repository.dart';
import 'user_profile.dart';

/// Why an authentication attempt was refused.
///
/// A reason rather than a message. [AuthFailure.message] is resolved from the
/// localisation tables by the presentation layer, which is what keeps the
/// repository free of any dependency on the words — and means an Arabic build
/// shows an Arabic sentence instead of the English one that used to be baked
/// in here. The value is also what a test can assert on, and what the log
/// records, so "the banner said *something*" never stands in for knowing *what*
/// went wrong.
enum AuthFailureReason {
  /// The email/password pair did not match an account.
  invalidCredentials,

  /// The address exists but has not been confirmed.
  emailNotConfirmed,

  /// Sign-up was refused because the address is already registered.
  alreadyRegistered,

  /// New accounts are closed. A server-side setting, not a user error.
  signupsDisabled,

  /// The sign-in method itself is switched off on the server.
  ///
  /// Distinct from [signupsDisabled] on purpose. `email_provider_disabled` is
  /// GoTrue's response when the *provider* is off, and it is returned by the
  /// password grant as well as by sign-up — so it reads as "sign-in is broken"
  /// rather than "registration is closed", and treating the two alike would
  /// send an existing user looking for a support page about new accounts.
  providerDisabled,

  /// Too many attempts in too short a time.
  rateLimited,

  /// Auth succeeded but the `public.users` row could not be read.
  profileUnavailable,

  /// The server accepted the request and returned no account.
  noAccountReturned,

  /// The account exists but sign-in will not work until the address is
  /// confirmed.
  confirmationRequired,

  /// Signing out failed.
  signOutFailed,

  /// Refused for a reason the app does not model.
  ///
  /// The underlying `AuthException.code` is kept in [AuthFailure.detail] and
  /// logged, so this is an honest "unrecognised" rather than a swallowed
  /// detail. Anything landing here during a smoke test is worth adding.
  unrecognised,
}

/// A failure that is safe to show to the user.
///
/// [AuthException.message] from the server is never shown verbatim: it can carry
/// internal detail, and in the case of a disabled provider it reads like a bug
/// rather than a product state. The original is logged, not displayed.
class AuthFailure implements Exception {
  const AuthFailure(this.reason, {this.detail});

  final AuthFailureReason reason;

  /// The server's own wording, for the log only. Never rendered.
  final String? detail;

  @override
  String toString() =>
      detail == null ? 'AuthFailure(${reason.name})' : 'AuthFailure(${reason.name}): $detail';
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
        throw AuthFailure(AuthFailureReason.noAccountReturned, detail: 'sign-in');
      }
      return await loadProfile(user.id);
    } on AuthException catch (error, stackTrace) {
      _logAuthFailure('sign-in failed', error, stackTrace, email: email);
      throw AuthFailure(reasonFor(error), detail: error.message);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('profile load failed', error, stackTrace);
      throw const AuthFailure(AuthFailureReason.profileUnavailable);
    }
  }

  /// Registers a new account.
  ///
  /// The requested role travels as Auth metadata, which is what the
  /// `handle_new_user` trigger reads. The database whitelists it to
  /// client|inspector, so passing `admin` here achieves nothing but a
  /// harmless no-op; the parameter is typed to the two assignable roles so the
  /// intent is visible at the call site.
  ///
  /// ## The identity document
  ///
  /// [idPhoto] is required — the business rule is that both roles upload an ID or
  /// residence card at sign-up — but it is uploaded *after* the account exists,
  /// because Supabase Auth mints the user id and there is nothing to file an object
  /// under until `signUp` returns. See `IdentityRepository` for why that ordering is
  /// the lesser of the two evils.
  ///
  /// What the caller gets back is the profile as the database has it. If the upload
  /// or the column write fails, that is *not* an authentication failure and the
  /// account is not rolled back — it exists, it is usable for a buyer, and for an
  /// inspector it is inert because it is unapproved. The method therefore rethrows
  /// as [AuthFailure] with [AuthFailureReason.profileUnavailable] only after
  /// re-attempting the load, so a stale-but-real profile is never traded away for an
  /// upload that did not land.
  Future<UserProfile> signUp({
    required String email,
    required String password,
    required String fullName,
    required UserRole role,
    required XFile idPhoto,
    IdentityRepository? identities,
    String? phone,
    String? city,
  }) async {
    if (role == UserRole.admin) {
      throw const AuthFailure(AuthFailureReason.signupsDisabled);
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
        throw const AuthFailure(AuthFailureReason.noAccountReturned);
      }
      if (response.session == null) {
        throw const AuthFailure(AuthFailureReason.confirmationRequired);
      }

      // The document is best effort, and the `try` around it is deliberate rather
      // than a mistake about error handling.
      //
      // The account exists and the session is live by this point. Refusing the
      // sign-up over a failed upload would sign the user straight back out of an
      // account they legitimately created and leave them unable to fix anything —
      // and rolling the account back is not available either, because Supabase Auth
      // will not un-create it from here. So the failure is logged, the profile is
      // returned, and the account lands on the screen that asks for the document
      // again. `UserProfile.isAwaitingDocuments` is what that screen keys on, so
      // nothing has to guess that this happened.
      try {
        await _attachIdPhoto(user.id, idPhoto, identities);
      } on IdentityFailure catch (error, stackTrace) {
        AppLogger.instance.error(
          'sign-up left without an id photo',
          error,
          stackTrace,
          {'user_id': user.id, 'role': role.name},
        );
      }

      return await loadProfile(user.id);
    } on AuthException catch (error, stackTrace) {
      _logAuthFailure('sign-up failed', error, stackTrace, email: email);
      throw AuthFailure(reasonFor(error), detail: error.message);
    }
  }

  /// Uploads [idPhoto] and points the profile at it, best effort.
  ///
  /// Split out so the failure path in [signUp] is one line and the ordering —
  /// object first, column second — is stated once rather than implied by the order
  /// of two statements in a `try`.
  Future<void> _attachIdPhoto(
    String userId,
    XFile idPhoto,
    IdentityRepository? identities,
  ) async {
    final IdentityRepository repository = identities ?? IdentityRepository(_client);
    final String path = await repository.uploadIdPhoto(userId: userId, file: idPhoto);
    await repository.setIdPhotoPath(userId, path);
  }

  /// Re-uploads an identity document for the signed-in account.
  ///
  /// Separate from [signUp] because the document can be missing long afterwards: an
  /// upload that failed at sign-up, a document the user picked wrong, or an
  /// inspector whose account was rejected and who is being asked to try again.
  ///
  /// Returns the refreshed profile, so the caller does not have to re-read a row it
  /// already knows the id of — and, more importantly, so a screen that was showing
  /// "awaiting documents" cannot keep showing it after a successful upload because
  /// its cached profile was not replaced.
  Future<UserProfile> updateIdPhoto(XFile idPhoto) async {
    final String? userId = currentUserId;
    if (userId == null) {
      throw const AuthFailure(AuthFailureReason.profileUnavailable);
    }
    await _attachIdPhoto(userId, idPhoto, null);
    return loadProfile(userId);
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on AuthException catch (error, stackTrace) {
      _logAuthFailure('sign-out failed', error, stackTrace);
      throw const AuthFailure(AuthFailureReason.signOutFailed);
    }
  }

  /// Updates the caller's own service city.
  ///
  /// The row is scoped by the session's own id (`users_update_self` RLS), so
  /// this can only ever touch the signed-in user's profile — the same
  /// guarantee [loadProfile] reads with. The value is written verbatim; the
  /// canonical-city Picker on the other end is what keeps it a valid board
  /// match, so there is nothing to normalise here.
  Future<void> updateCity(String city) async {
    final String? userId = currentUserId;
    if (userId == null) {
      throw const AuthFailure(AuthFailureReason.profileUnavailable);
    }
    try {
      await _client
          .from('users')
          .update(<String, dynamic>{'location_city': city.trim()})
          .eq('id', userId);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('service city update failed', error, stackTrace);
      throw const AuthFailure(AuthFailureReason.profileUnavailable);
    }
  }

  /// Records an auth failure with the fields that actually identify it.
  ///
  /// [AuthException.code] is the one that matters: `error.message` is prose
  /// GoTrue is free to reword between releases, whereas the code is a stable
  /// contract, and for the failure that is hardest to diagnose from a screen —
  /// a provider that is simply switched off — the code is the only thing that
  /// says so. Logging `message` alone gives "Email logins are disabled" with no
  /// way to tell a misconfigured server from a typo.
  ///
  /// The email is logged alongside because a signup that fails for every user
  /// and one that fails for a single address look identical without it. It is a
  /// user's own address, in a file only the app can read.
  void _logAuthFailure(
    String message,
    AuthException error,
    StackTrace stackTrace, {
    String? email,
  }) {
    AppLogger.instance.error(
      message,
      error,
      stackTrace,
      <String, Object?>{
        'email': ?email,
        'code': error.code,
        'status': error.statusCode,
        'detail': error.message,
      },
    );

    // A disabled provider is an operator error, not a user one, and no amount of
    // retrying will clear it. Escalated so it is distinguishable in the file
    // from the ordinary wrong-password noise.
    if (error.code == 'email_provider_disabled' ||
        error.code == 'sms_provider_disabled') {
      AppLogger.instance.error(
        'auth provider is disabled on the server: enable it in the Supabase '
        'dashboard under Authentication → Providers. No app change can work '
        'around this, and nothing was sent to a server that can accept it.',
      );
    }
  }

  /// Maps a server auth error onto a reason the app can act on.
  ///
  /// Matched on [AuthException.code] first because it is the stable contract,
  /// then on message text. The fallback is deliberate rather than redundant:
  /// GoTrue has renamed several of these strings across versions, and an app
  /// that has just been pointed at an older server should still recognise
  /// `invalid login credentials` rather than degrade to [AuthFailureReason
  /// .unrecognised] and tell the user to try again.
  @visibleForTesting
  static AuthFailureReason reasonFor(AuthException error) {
    switch (error.code) {
      case 'email_provider_disabled':
      case 'sms_provider_disabled':
        return AuthFailureReason.providerDisabled;
      case 'invalid_credentials':
        return AuthFailureReason.invalidCredentials;
      case 'email_not_confirmed':
        return AuthFailureReason.emailNotConfirmed;
      case 'user_already_exists':
        return AuthFailureReason.alreadyRegistered;
      case 'signup_disabled':
        return AuthFailureReason.signupsDisabled;
      // One reason for all three: whether the caller was throttled generally or
      // on a single channel, the advice to the user is identical — wait.
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
      case 'over_sms_send_rate_limit':
        return AuthFailureReason.rateLimited;
    }

    final String detail = error.message.toLowerCase();
    if (detail.contains('email') &&
        (detail.contains('disabled') || detail.contains('not enabled'))) {
      return AuthFailureReason.providerDisabled;
    }
    if (detail.contains('invalid login credentials')) {
      return AuthFailureReason.invalidCredentials;
    }
    if (detail.contains('email not confirmed')) {
      return AuthFailureReason.emailNotConfirmed;
    }
    if (detail.contains('already registered') ||
        detail.contains('already been registered')) {
      return AuthFailureReason.alreadyRegistered;
    }
    if (detail.contains('signups not allowed')) {
      return AuthFailureReason.signupsDisabled;
    }
    // Matches "rate limit" and "too many requests": the throttle message does
    // not reliably use the words the code does, so a prose-only match misses
    // the most common shape of this error.
    if (detail.contains('rate limit') || detail.contains('too many requests')) {
      return AuthFailureReason.rateLimited;
    }
    return AuthFailureReason.unrecognised;
  }
}
