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

/// The inspector's job board: pending requests in their city, newest first.
///
/// Watches [authControllerProvider] the same way [myRequestsProvider] does, so a
/// sign-out cannot leave the previous inspector's board on screen. It takes no
/// user id because RLS decides which city's requests are visible; see
/// [InspectionRepository.listBoard].
final jobBoardProvider = FutureProvider<List<InspectionRequest>>((Ref ref) async {
  ref.watch(authControllerProvider);
  return ref.watch(inspectionRepositoryProvider).listBoard();
});

/// The signed-in inspector's own jobs, newest first.
///
/// This one has to wait for the profile: the repository narrows on
/// `inspector_id`, because the participant RLS policy cannot tell which side of
/// a request the caller was. See [InspectionRepository.listForInspector].
final myJobsProvider = FutureProvider<List<InspectionRequest>>((Ref ref) async {
  final UserProfile? profile = await ref.watch(authControllerProvider.future);
  if (profile == null) return const <InspectionRequest>[];
  return ref.watch(inspectionRepositoryProvider).listForInspector(profile.id);
});

/// One request, as the inspector's detail page sees it.
///
/// A family rather than a cache hit off a list, because the inspector can reach
/// a job from either the board or their jobs list, and neither list reliably
/// holds a row that is now on the *other* list (accepting moves a request
/// between them). Fetching by id also lets an action invalidate just this row so
/// the page shows the post-transition status without refetching both lists.
final inspectorJobProvider =
    FutureProvider.family<InspectionRequest, String>((Ref ref, String id) {
      ref.watch(authControllerProvider);
      return ref.watch(inspectionRepositoryProvider).byId(id);
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

  /// The three inspector status writes share one shape: run the transition,
  /// then let every index that can show the request refetch so its new status
  /// is everywhere immediately. Invalidation rather than optimistic updates,
  /// for the same reason as [create] — the trigger is what decides the
  /// transition is legal, so the database's answer is the only truthful one.
  ///
  /// Throws on failure, like [cancel], recording the error in [state] as well.
  Future<void> _transition(
    Future<void> Function() write,
    String id,
  ) async {
    state = const AsyncLoading();
    try {
      await write();
      state = const AsyncData(null);
      ref.invalidate(jobBoardProvider);
      ref.invalidate(myJobsProvider);
      ref.invalidate(inspectorJobProvider(id));
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  /// Claims a pending request. Invalidates the shared indexes plus this one
  /// row, so the board drops it and the jobs list picks it up.
  Future<void> accept(String id) {
    return _transition(
      () => ref.read(inspectionRepositoryProvider).accept(id),
      id,
    );
  }

  Future<void> start(String id) {
    return _transition(
      () => ref.read(inspectionRepositoryProvider).start(id),
      id,
    );
  }

  Future<void> complete(String id) {
    return _transition(
      () => ref.read(inspectionRepositoryProvider).complete(id),
      id,
    );
  }
}

final inspectionRequestControllerProvider =
    NotifierProvider<InspectionRequestController, AsyncValue<void>>(
      InspectionRequestController.new,
    );
