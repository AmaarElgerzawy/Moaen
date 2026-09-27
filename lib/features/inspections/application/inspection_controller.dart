import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../auth/user_profile.dart';
import '../data/inspection_repository.dart';
import '../domain/inspection_draft.dart';
import '../domain/inspection_request.dart';

final inspectionRepositoryProvider = Provider<InspectionRepository>(
  (Ref ref) => InspectionRepository(ref.watch(supabaseClientProvider)),
);

/// The signed-in buyer's requests, newest first.
///
/// Watches [authControllerProvider] for its invalidation side effect, not its
/// value. Without that, a sign-out followed by a different sign-in would show
/// the previous buyer's requests on screen, because this provider would still be
/// holding its cached value — a privacy bug that no single test would catch,
/// since each one starts signed in.
///
/// The read takes no user id because RLS decides visibility; see
/// [InspectionRepository.listForClient].
final myRequestsProvider = FutureProvider<List<InspectionRequest>>((
  Ref ref,
) async {
  ref.watch(authControllerProvider);
  return ref.watch(inspectionRepositoryProvider).listForClient();
});

/// The request the dashboard leads with, or null when the buyer has none.
///
/// A separate provider from [myRequestsProvider] because the dashboard needs one
/// row, and fetching the whole history to show the newest is the kind of request
/// that grows without anyone noticing.
final dashboardRequestProvider = FutureProvider<InspectionRequest?>((Ref ref) {
  ref.watch(authControllerProvider);
  return ref.watch(inspectionRepositoryProvider).latestForClient();
});

/// The id the repository writes under.
///
/// Awaits the auth provider's *future* rather than reading `.value`, and that
/// distinction is load-bearing. `authControllerProvider` is an `AsyncNotifier`,
/// so on the very first read — which is exactly when a write happens, because
/// nothing has watched it yet — it is `AsyncLoading` and `.value` is null even
/// though a session exists and resolves a frame later. Reading `.value` here
/// threw a `StateError` on every first write; awaiting the future waits for the
/// session to resolve.
///
/// Throws if there genuinely is no session: a request with a null `client_id`
/// would be rejected by the schema with an error about a column rather than
/// about the session, which is no help to anyone.
Future<String> _clientId(Ref ref) async {
  final UserProfile? profile = await ref.read(authControllerProvider.future);
  if (profile == null) {
    throw StateError('inspection write attempted with no signed-in user');
  }
  return profile.id;
}

/// Writes: create and cancel.
///
/// Separate from the read providers because these are user-initiated and want a
/// loading state of their own — [myRequestsProvider] being `AsyncLoading` during
/// a cancel would blank the list the user is looking at.
class InspectionRequestController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Creates a request, returning it so the caller can show the assigned
  /// reference.
  ///
  /// Invalidates the read providers on success rather than optimistically
  /// inserting the new row: the database is what assigns `reference_no` and
  /// decides `created_at`, so the row that comes back is the only truthful one.
  ///
  /// Rethrows so the caller can react to a failure, while also recording it in
  /// [state] so a rebuild keeps showing the error rather than silently clearing
  /// it. A caller that only reads [state] is a supported way to use this.
  Future<InspectionRequest> create(InspectionDraft draft) async {
    state = const AsyncLoading();
    try {
      final InspectionRequest created = await ref
          .read(inspectionRepositoryProvider)
          .create(draft, await _clientId(ref));
      state = const AsyncData(null);
      ref.invalidate(myRequestsProvider);
      ref.invalidate(dashboardRequestProvider);
      return created;
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  /// Cancels a request.
  ///
  /// Throws on failure, like [create]. The earlier version recorded the error in
  /// [state] and returned normally, which pushed every caller into reading the
  /// state back afterwards to find out what happened — and that read can return
  /// a rebuilt notifier's initial value rather than the failure.
  Future<void> cancel(String id) async {
    state = const AsyncLoading();
    try {
      await ref.read(inspectionRepositoryProvider).cancel(id);
      state = const AsyncData(null);
      ref.invalidate(myRequestsProvider);
      ref.invalidate(dashboardRequestProvider);
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

final inspectionRequestControllerProvider =
    NotifierProvider<InspectionRequestController, AsyncValue<void>>(
      InspectionRequestController.new,
    );
