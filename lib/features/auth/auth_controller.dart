import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/logging/app_logger.dart';
import 'auth_repository.dart';
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

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required UserRole role,
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
        phone: phone,
        city: city,
      ),
    );
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AsyncData(null);
  }
}
