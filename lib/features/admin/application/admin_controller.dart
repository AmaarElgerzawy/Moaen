import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../auth/user_profile.dart';
import '../../../core/pricing/commission.dart';
// Imported for its side effect: `commissionProvider` is re-exported through this
// layer so the settings tab has one import for the admin feature, but it is declared
// in core because the create-request form and the inspector's offer sheet read it too
// and neither may depend on the admin feature.
import '../../../core/pricing/commission_controller.dart';
import '../../inspections/application/inspection_controller.dart';
import '../../inspections/domain/inspection_centre.dart';
import '../../inspections/domain/inspection_request.dart';
import '../../inspections/domain/order_filter.dart';
import '../data/admin_repository.dart';
import '../domain/financial_overview.dart';
import '../domain/order_summary.dart';

final adminRepositoryProvider = Provider<AdminRepository>(
  (Ref ref) => AdminRepository(ref.watch(supabaseClientProvider)),
);

/// Every administrative read.
///
/// All of them watch [authControllerProvider] for its invalidation side effect
/// rather than its value, for the reason [myRequestsProvider] does: a sign-out
/// followed by a different sign-in would otherwise leave the previous session's
/// roster, balances or orders on screen. An admin panel is the one screen where
/// that is the worst possible leak.
final reviewQueueProvider = FutureProvider<List<UserProfile>>((Ref ref) async {
  ref.watch(authControllerProvider);
  return ref.watch(adminRepositoryProvider).reviewQueue();
});

/// The accounts list, filtered on the client.
///
/// Filtered rather than queried because the search is over a roster that is
/// already capped at 300 rows and the keystrokes arrive faster than a round trip
/// could answer them. The alternative — a query per character typed — makes the
/// panel feel broken on a slow connection and tells the server the names of
/// everyone in the platform one prefix at a time.
final adminUsersProvider = FutureProvider<List<UserProfile>>((Ref ref) async {
  ref.watch(authControllerProvider);
  return ref.watch(adminRepositoryProvider).listUsers();
});

final adminCentresProvider = FutureProvider<List<InspectionCentre>>((
  Ref ref,
) async {
  ref.watch(authControllerProvider);
  return ref.watch(adminRepositoryProvider).listCentres();
});

final financialsProvider = FutureProvider<FinancialOverview>((Ref ref) async {
  ref.watch(authControllerProvider);
  return ref.watch(adminRepositoryProvider).financials();
});

final orderSummaryProvider = FutureProvider<List<OrderSummary>>((Ref ref) async {
  ref.watch(authControllerProvider);
  return ref.watch(adminRepositoryProvider).orderSummary();
});

/// The orders monitor, filtered in the database.
///
/// A [FilterNotifier] rather than a family keyed on the filter object, because the
/// filter changes on every keystroke and a family would leave one cached request per
/// intermediate value — each a query the panel fired and abandoned. One notifier
/// holds the current filter and refetches only the last one.
class AdminOrdersFilter extends Notifier<OrderFilter> {
  @override
  OrderFilter build() {
    ref.watch(authControllerProvider);
    return OrderFilter.none;
  }

  /// Replaces the filter outright, which is what the controls call.
  ///
  /// Takes the whole value rather than the six setters: `OrderFilter.copyWith`
  /// needs explicit `clear*` flags to unset a field, so a per-control setter API
  /// here would have to expose those flags anyway and would end up with the same
  /// shape one level up.
  void set(OrderFilter filter) => state = filter;
}

final adminOrdersFilterProvider =
    NotifierProvider<AdminOrdersFilter, OrderFilter>(
      AdminOrdersFilter.new,
    );

final adminOrdersProvider = FutureProvider<List<InspectionRequest>>((
  Ref ref,
) async {
  final OrderFilter filter = ref.watch(adminOrdersFilterProvider);
  return ref.watch(inspectionRepositoryProvider).listAll(filter: filter);
});

/// How many approval emails are queued but unsent.
///
/// Polled by nothing. It is a reading of the outbox, and the panel shows it so that
/// "did those inspectors get told" has an answer on the screen — the honest answer
/// being a count rather than a promise, because the edge function that drains the
/// outbox may not be deployed at all.
final pendingNotificationsProvider = FutureProvider<int>((Ref ref) async {
  ref.watch(authControllerProvider);
  return ref.watch(adminRepositoryProvider).pendingNotifications();
});

/// Every administrative write.
///
/// One notifier for the five sections, for the reason [ReportController] is one: each
/// write invalidates the reads that show its result, and a caller that has to
/// remember which is a caller that eventually forgets. The state is a single
/// `AsyncValue<void>` so a tab can show one spinner per section rather than five.
class AdminController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Runs [write], then invalidates every read the panel draws.
  ///
  /// Invalidates *all* of them rather than picking per method: the sections are
  /// independent, so a refresh costs one query each and gets the panel right. Being
  /// clever about which ones changed would be a cache-coherence bug waiting for the
  /// first write that changes something a reader did not obviously depend on — the
  /// suspension toggle, which moves an inspector between the queue and the accounts
  /// list, being the obvious one.
  Future<void> _run(Future<void> Function(AdminRepository repository) write) async {
    state = const AsyncLoading();
    try {
      await write(ref.read(adminRepositoryProvider));
      state = const AsyncData(null);
      ref.invalidate(reviewQueueProvider);
      ref.invalidate(adminUsersProvider);
      ref.invalidate(adminCentresProvider);
      ref.invalidate(commissionProvider);
      ref.invalidate(pendingNotificationsProvider);
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> approve(String userId) =>
      _run((AdminRepository repository) => repository.approve(userId));

  Future<void> reject(String userId, String reason) =>
      _run((AdminRepository repository) => repository.reject(userId, reason));

  Future<void> setBlocked(
    String userId, {
    required bool blocked,
    String? reason,
  }) => _run(
    (AdminRepository repository) => repository.setBlocked(
      userId,
      blocked: blocked,
      reason: reason,
    ),
  );

  Future<void> setCentreBlocked(
    String centreId, {
    required bool blocked,
  }) => _run(
    (AdminRepository repository) => repository.setCentreBlocked(
      centreId,
      blocked: blocked,
    ),
  );

  /// Saves the commission.
  ///
  /// Also invalidates [commissionProvider], which is what the create-request form
  /// watches. An admin who changes the commission and a buyer who files a request in
  /// the same minute should agree about the price, and this is the edge that makes
  /// them: the snapshot is taken by the database at insert, from the row this
  /// invalidation refetches.
  Future<void> setCommission(Commission commission) =>
      _run((AdminRepository repository) => repository.setCommission(commission));

  /// Clears a recorded failure so a tab's banner goes away on the next attempt.
  ///
  /// Without it a panel that failed once shows the error forever, because
  /// `AsyncValue` has no notion of "the user has seen this and moved on" and the
  /// banner is derived from it. Explicit rather than automatic on build: a rebuild
  /// happens on tab switches too, and swallowing the error on a rebuild would hide
  /// a write that genuinely failed.
  void clearError() {
    if (state.hasError) state = const AsyncData(null);
  }
}

final adminControllerProvider =
    NotifierProvider<AdminController, AsyncValue<void>>(AdminController.new);