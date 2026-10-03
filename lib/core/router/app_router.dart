import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/admin_home_page.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/presentation/access_restricted_page.dart';
import '../../features/auth/sign_in_page.dart';
import '../../features/auth/user_profile.dart';
import '../../features/inspections/presentation/client_dashboard_page.dart';
import '../../features/inspections/presentation/create_request_page.dart';
import '../../features/inspections/presentation/inspector_home_page.dart';
import '../../features/inspections/presentation/inspector_job_detail_page.dart';
import '../../features/inspections/presentation/inspector_market_page.dart';
import '../../features/inspections/presentation/my_requests_page.dart';
import '../../features/inspections/presentation/report_entry_page.dart';
import '../../features/inspections/presentation/report_page.dart';
import '../../features/inspections/presentation/request_detail_page.dart';
import '../../features/home/role_landing_page.dart';

/// Route paths, in one place so the redirect logic and the route table cannot
/// drift apart.
abstract final class AppRoutes {
  static const String signIn = '/sign-in';
  static const String home = '/home';

  /// The buyer's home.
  ///
  /// A separate path from [home] because [home] is the role-agnostic landing screen
  /// the redirect falls back to — the one place a signed-in account with no
  /// role-specific destination of its own ends up.
  static const String dashboard = '/dashboard';
  static const String createRequest = '/requests/new';
  static const String myRequests = '/requests';
  static const String requestDetail = '/requests/:id';

  /// The buyer's report and the inspector's form that produces it. Both are keyed
  /// on the *inspection's* id, not the report row's, because the report row does
  /// not exist until the form has been submitted once — so the buyer's reports
  /// tab cannot link to a report by its own id without a lookup that would 404 on
  /// the one screen a buyer reaches it from.
  static const String report = '/requests/:id/report';
  static const String reportEntry = '/requests/:id/report/entry';

  /// The inspector's home: board, my jobs, profile.
  static const String inspector = '/inspector';
  static const String inspectorJobDetail = '/inspector/jobs/:id';

  /// The market the inspector picks jobs from. A separate pushed route rather
  /// than a fifth tab, because the design gives the board's `عرض كل` a screen of
  /// its own with no bottom bar at all.
  static const String inspectorMarket = '/inspector/market';

  /// The detail path for one request, from the inspector's side.
  static String inspectorJobDetailPath(String id) => '/inspector/jobs/$id';

  /// Where an account lands when it cannot use the platform yet: an inspector
  /// awaiting an admin's decision, one turned down, or any account suspended.
  ///
  /// A route rather than a flag the screens each read, so the rule lives in exactly
  /// one place. See the redirect below.
  static const String restricted = '/restricted';

  /// The admin panel. Its own path so a role check can send an admin here and
  /// refuse everyone else, both from the same redirect.
  static const String admin = '/admin';
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
        path: AppRoutes.reportEntry,
        name: 'reportEntry',
        builder: (_, GoRouterState state) =>
            ReportEntryPage(id: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.report,
        name: 'report',
        builder: (_, GoRouterState state) =>
            ReportPage(id: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.inspector,
        builder: (_, _) => const InspectorHomePage(),
      ),
      GoRoute(
        path: AppRoutes.inspectorJobDetail,
        // `inspectorJob` rather than `inspectorJobDetail`: the job detail page is
        // reached from the tasks list as often as from the board, and the two
        // callers should not need to know which one they came off.
        name: 'inspectorJob',
        builder: (_, GoRouterState state) =>
            InspectorJobDetailPage(id: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.inspectorMarket,
        name: 'inspectorMarket',
        builder: (_, _) => const InspectorMarketPage(),
      ),
      GoRoute(
        path: AppRoutes.restricted,
        builder: (_, _) => const AccessRestrictedPage(),
      ),
      GoRoute(
        path: AppRoutes.admin,
        name: 'admin',
        builder: (_, _) => const AdminHomePage(),
      ),
    ],
    redirect: (BuildContext context, GoRouterState state) {
      // Still restoring a persisted session: decide nothing yet, or a returning
      // user would be flashed the sign-in screen on every cold start.
      if (auth.isLoading) return null;

      final UserProfile? profile = auth.value;
      final String at = state.matchedLocation;
      final bool atSignIn = at == AppRoutes.signIn;
      final bool atHome = at == AppRoutes.home;
      final bool atRestricted = at == AppRoutes.restricted;
      final bool atAdmin = at == AppRoutes.admin;

      if (profile == null) return atSignIn ? null : AppRoutes.signIn;
      if (atSignIn) return AppRoutes.home;

      // The access gate, ahead of every role rule below.
      //
      // Anywhere except the restricted screen itself, so an account that cannot
      // work sees the screen that explains why — whichever of the eight routes it
      // tried to reach. Without this a suspended inspector who had the app open
      // would keep a working board until they pulled to refresh, which is the
      // failure mode RLS is supposed to make impossible and the UI would paper
      // over. The database still refuses the reads underneath; this only stops the
      // screen from pretending they succeeded.
      if (!profile.canOperate && !atRestricted) return AppRoutes.restricted;

      // Roles have a real home now. The redirect is on /home specifically
      // rather than on every route, so a user who deep-links straight to a
      // request or job is not bounced out of it by the role check.
      if (atHome && profile.role == UserRole.client) return AppRoutes.dashboard;
      if (atHome && profile.role == UserRole.inspector) return AppRoutes.inspector;
      if (atHome && profile.role == UserRole.admin) return AppRoutes.admin;

      // A working account that lands on the restricted screen has been approved or
      // un-suspended since it was last built, so it goes home rather than being told
      // it is still locked out.
      //
      // Guarded on [UserProfile.canOperate] rather than unconditional. Unconditional
      // looks harmless — the gate above already declined to redirect *away* from the
      // restricted screen — and is not: go_router re-runs `redirect` for the location
      // it is returning, so an account that still cannot operate would be sent from
      // `/restricted` to `/home`, the gate would send it back, and the two would
      // trade the location until go_router gave up. The suspended inspector would
      // then be left on whichever page the loop happened to stop at, which is the one
      // thing this gate exists to prevent.
      if (atRestricted) return profile.canOperate ? AppRoutes.home : null;

      // The panel's own gate. An admin is the only role whose *destination* is
      // administrative, and RLS backs the reads up — but sending a buyer to a page
      // of empty panels and "you are not allowed" errors is a worse experience than
      // simply not having the page.
      if (atAdmin && profile.role != UserRole.admin) return AppRoutes.home;

      return null;
    },
  );
});
