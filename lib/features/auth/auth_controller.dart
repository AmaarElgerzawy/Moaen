import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/logging/app_logger.dart';
import '../../core/media/photo_picker.dart';
import 'auth_repository.dart';
import 'data/identity_repository.dart';
import 'user_profile.dart';

/// The single Supabase client, resolved after bootstrap.
///
/// Overridden in tests with a fake, so nothing in the widget tree reaches for
/// a global.
final supabaseClientProvider = Provider<SupabaseClient>(
  (Ref ref) => Supabase.instance.client,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (Ref ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

/// The identity document repository.
///
/// A provider rather than a bare construction because the sign-up form and the
/// "your document did not arrive" screen both reach it, and a widget test that
/// exercises either must be able to substitute it — `AuthRepository` takes one as an
/// optional parameter precisely so `AuthController` can pass this override down.
final identityRepositoryProvider = Provider<IdentityRepository>(
  (Ref ref) => IdentityRepository(ref.watch(supabaseClientProvider)),
);

/// The device's photo library, for the sign-up form's identity control.
///
/// The same seam as `photoPickerProvider` in the inspections feature, and for the
/// same reason: `image_picker` opens a native gallery, which a widget test cannot
/// drive. Declared here rather than reused across features because auth must not
/// import from inspections — the dependency would run the wrong way.
final identityPhotoPickerProvider = Provider<PhotoPicker>(
  (Ref ref) => const SystemPhotoPicker(),
);

/// Signed-in identity, or null when signed out.
///
/// [AsyncLoading] is the initial value while a persisted session is restored,
/// which the router reads as "not yet known" and waits on rather than bouncing
/// the user to the sign-in screen.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, UserProfile?>(AuthController.new);

class AuthController extends AsyncNotifier<UserProfile?> {
  @override
  Future<UserProfile?> build() async {
    final AuthRepository repository = ref.watch(authRepositoryProvider);
    final String? userId = repository.currentUserId;
    if (userId == null) return null;

    try {
      return await repository.loadProfile(userId);
    } catch (error, stackTrace) {
      // A token that survives a schema change or a revoked profile would
      // otherwise trap the user on a blank loading screen.
      AppLogger.instance.error('session restore failed', error, stackTrace);
      await repository.signOut();
      return null;
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(authRepositoryProvider)
          .signIn(email: email, password: password),
    );
  }

  /// Registers an account, with its identity document.
  ///
  /// [idPhoto] is required rather than optional-with-a-warning, because the rule is
  /// that both roles upload an ID or residence card at sign-up. Making it optional
  /// here and required only in the form would leave the same gap this feature exists
  /// to close: an account with no document, that an admin's queue cannot review.
  ///
  /// The upload is passed through rather than performed here, because the object
  /// cannot be filed until Supabase Auth has minted the id — so the repository does
  /// the upload itself, immediately after the signup call returns. See
  /// `IdentityRepository` for why that ordering is the lesser of two evils.
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required UserRole role,
    required XFile idPhoto,
    String? phone,
    String? city,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signUp(
        email: email,
        password: password,
        fullName: fullName,
        role: role,
        idPhoto: idPhoto,
        identities: ref.read(identityRepositoryProvider),
        phone: phone,
        city: city,
      ),
    );
  }

  /// Re-uploads an identity document for the signed-in account.
  ///
  /// Returns whether the upload landed, because a retry is a second explicit press
  /// of a button the user is looking at: swallowing the failure would leave the
  /// screen looking exactly as it did before, which is the one thing that makes a
  /// failed retry indistinguishable from a button that does nothing.
  ///
  /// On failure the previous profile is kept rather than dropped to null. Letting
  /// `AsyncValue.guard`'s error value stand would bounce the user to the sign-in
  /// screen over a photo that failed to upload — losing the account over a storage
  /// outage is the worst possible answer to the least likely failure.
  Future<bool> updateIdPhoto(XFile idPhoto) async {
    final UserProfile? before = state.value;
    state = await AsyncValue.guard(
      () => ref
          .read(authRepositoryProvider)
          .updateIdPhoto(idPhoto),
    );

    if (state.hasError) {
      final Object error = state.error!;
      final StackTrace stackTrace = state.stackTrace ?? StackTrace.current;
      AppLogger.instance.error('id photo retry failed', error, stackTrace);
      if (before != null) state = AsyncData(before);
      return false;
    }

    return true;
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AsyncData(null);
  }

  /// Changes the signed-in inspector's service city.
  ///
  /// The update is scoped to the caller's own row by RLS. The in-memory profile
  /// is patched in place rather than refetched, so the job board header, the
  /// profile tab and — after the caller invalidates it — the board itself all
  /// reflect the new city without a round trip.
  Future<void> updateCity(String city) async {
    await ref.read(authRepositoryProvider).updateCity(city);
    final UserProfile? current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(locationCity: city.trim()));
  }
}
