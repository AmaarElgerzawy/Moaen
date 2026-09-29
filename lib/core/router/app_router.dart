import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_controller.dart';
import '../../features/auth/sign_in_page.dart';
import '../../features/auth/user_profile.dart';
import '../../features/inspections/presentation/client_dashboard_page.dart';
import '../../features/inspections/presentation/create_request_page.dart';
import '../../features/inspections/presentation/inspector_home_page.dart';
import '../../features/inspections/presentation/inspector_job_detail_page.dart';
import '../../features/inspections/presentation/my_requests_page.dart';
import '../../features/inspections/presentation/request_detail_page.dart';
import '../../features/home/role_landing_page.dart';

/// Route paths, in one place so the redirect logic and the route table cannot
/// drift apart.
abstract final class AppRoutes {
  static const String signIn = '/sign-in';
  static const String home = '/home';

  /// The buyer's home. A separate path from [home] because [home] is the
  /// role-agnostic landing screen an admin or an unknown role still sees.
  static const String dashboard = '/dashboard';
  static const String createRequest = '/requests/new';
  static const String myRequests = '/requests';
  static const String requestDetail = '/requests/:id';

  /// The inspector's home: board, my jobs, profile.
  static const String inspector = '/inspector';
  static const String inspectorJobDetail = '/inspector/jobs/:id';

  /// The detail path for one request, from the inspector's side.
  static String inspectorJobDetailPath(String id) => '/inspector/jobs/$id';
}

/// The application router, rebuilt whenever the auth state changes.
///
/// Rebuilding on an auth transition is deliberate rather than a shortcut. A
/// `refreshListenable` bridge would preserve a stale navigation stack across a
/// sign-out, which is precisely the state that must not survive. Auth changes
/// are rare, so a discarded stack costs nothing.
final routerProvider = Provider<GoRouter>((Ref ref) {
  final AsyncValue<UserProfile?> auth = ref.watch(authControllerProvider);

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
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (_, _) => const ClientDashboardPage(),
      ),
      GoRoute(
        path: AppRoutes.createRequest,
        // Named so the dashboard and the requests list can both reach it without
        // either knowing the other's route table.
        name: 'createRequest',
        builder: (_, _) => const CreateRequestPage(),
      ),
      GoRoute(
        path: AppRoutes.myRequests,
        name: 'myRequests',
        builder: (_, _) => const MyRequestsPage(),
      ),
      GoRoute(
        path: AppRoutes.requestDetail,
        name: 'requestDetail',
        builder: (_, GoRouterState state) =>
            RequestDetailPage(id: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.inspector,
        builder: (_, _) => const InspectorHomePage(),
      ),
      GoRoute(
        path: AppRoutes.inspectorJobDetail,
        name: 'inspectorJobDetail',
        builder: (_, GoRouterState state) =>
            InspectorJobDetailPage(id: state.pathParameters['id'] ?? ''),
      ),
    ],
    redirect: (BuildContext context, GoRouterState state) {
      // Still restoring a persisted session: decide nothing yet, or a returning
      // user would be flashed the sign-in screen on every cold start.
      if (auth.isLoading) return null;

      final UserProfile? profile = auth.value;
      final bool atSignIn = state.matchedLocation == AppRoutes.signIn;
      final bool atHome = state.matchedLocation == AppRoutes.home;

      if (profile == null) return atSignIn ? null : AppRoutes.signIn;
      if (atSignIn) return AppRoutes.home;

      // Roles have a real home now. The redirect is on /home specifically
      // rather than on every route, so a user who deep-links straight to a
      // request or job is not bounced out of it by the role check.
      if (atHome && profile.role == UserRole.client) return AppRoutes.dashboard;
      if (atHome && profile.role == UserRole.inspector) return AppRoutes.inspector;

      return null;
    },
  );
});
