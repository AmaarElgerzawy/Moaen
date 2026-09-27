import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_controller.dart';
import '../../features/auth/sign_in_page.dart';
import '../../features/home/role_landing_page.dart';

/// Route paths, in one place so the redirect logic and the route table cannot
/// drift apart.
abstract final class AppRoutes {
  static const String signIn = '/sign-in';
  static const String home = '/home';
}

/// The application router, rebuilt whenever the auth state changes.
///
/// Rebuilding on an auth transition is deliberate rather than a shortcut. A
/// `refreshListenable` bridge would preserve a stale navigation stack across a
/// sign-out, which is precisely the state that must not survive. Auth changes
/// are rare, so a discarded stack costs nothing.
final routerProvider = Provider<GoRouter>((Ref ref) {
  final AsyncValue<Object?> auth = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: AppRoutes.signIn,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.signIn,
        builder: (_, _) => const SignInPage(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => const RoleLandingPage(),
      ),
    ],
    redirect: (BuildContext context, GoRouterState state) {
      // Still restoring a persisted session: decide nothing yet, or a returning
      // user would be flashed the sign-in screen on every cold start.
      if (auth.isLoading) return null;

      final bool signedIn = auth.value != null;
      final bool atSignIn = state.matchedLocation == AppRoutes.signIn;

      if (!signedIn) return atSignIn ? null : AppRoutes.signIn;
      if (atSignIn) return AppRoutes.home;
      return null;
    },
  );
});
