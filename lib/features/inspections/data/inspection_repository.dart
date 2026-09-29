import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/inspection_draft.dart';
import '../domain/inspection_request.dart';

/// A failure that is safe to show to the buyer.
///
/// As with [AuthFailure], the server's message is logged rather than displayed:
/// a PostgREST error names tables and columns, which is not something to show
/// someone trying to book a car inspection.
class InspectionFailure implements Exception {
  const InspectionFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// All reads and writes of `car_inspections` go through here.
///
/// Every method takes the caller's user id from the caller rather than reading
/// the session, for the same reason `AuthRepository` does: it keeps the
/// transport types out of the controller and lets a widget test substitute this
/// class without a network.
class InspectionRepository {
  InspectionRepository(this._client);

  final SupabaseClient _client;

  static const String _table = 'car_inspections';

  /// The signed-in buyer's own requests, newest first.
  ///
  /// Takes no user id, and that is deliberate rather than a shortcut. RLS
  /// restricts the result to `client_id = auth.uid()`, so there is nothing to
  /// filter here and adding a `client_id` predicate would be redundant rather
  /// than defensive. A parameter that is accepted and then ignored is worse than
  /// no parameter: it reads as though the caller decides whose requests these
  /// are, and a future edit could start believing it.
  ///
  /// The ordering matches the index in migration 0001.
  Future<List<InspectionRequest>> listForClient() async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from(_table)
          .select()
          .order('created_at', ascending: false);

      return rows.map(InspectionRequest.fromRow).toList();
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('request list failed', error, stackTrace);
      throw const InspectionFailure(
        'Could not load your requests. Please try again.',
      );
    }
  }

  /// The request the dashboard leads with: the buyer's most recent one.
  ///
  /// "Most recent", not "most urgent" and not "still open", and that is a
  /// deliberate choice over two more obvious rules.
  ///
  /// Filtering to open requests — the obvious reading of "active" — means that
  /// the instant an inspection is completed the dashboard claims there is no
  /// active request and offers to book another. The report the buyer paid for
  /// and travelled for becomes unreachable from the screen they open first. The
  /// whole product is the report; a rule that hides it on completion is wrong
  /// however tidy it looks in the query.
  ///
  /// Ranking an open request above a completed one is also rejected. A buyer
  /// realistically has one live request, and the moment they do not, the most
  /// recent thing that happened to them is the one worth showing. An invented
  /// priority would need its own tests and would be a product decision made in
  /// a query.
  ///
  /// Cancelled requests are included for the same reason: a buyer who cancelled
  /// should see that it happened, not an empty state implying nothing ever
  /// existed. [InspectionRequest.isOpen] still separates open from settled on
  /// the requests list, which is where history belongs.
  Future<InspectionRequest?> latestForClient() async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from(_table)
          .select()
          .order('created_at', ascending: false)
          .limit(1);

      return rows.isEmpty ? null : InspectionRequest.fromRow(rows.first);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('dashboard request lookup failed', error, stackTrace);
      throw const InspectionFailure(
        'Could not load your active request. Please try again.',
      );
    }
  }

  Future<InspectionRequest> create(InspectionDraft draft, String clientId) async {
    try {
      final Map<String, dynamic> row =
          await _client.from(_table).insert(draft.toRow(clientId)).select().single();
      return InspectionRequest.fromRow(row);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('request creation failed', error, stackTrace);
      throw InspectionFailure(_messageFor(error));
    }
  }

  Future<InspectionRequest> byId(String id) async {
    try {
      final Map<String, dynamic> row =
          await _client.from(_table).select().eq('id', id).single();
      return InspectionRequest.fromRow(row);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('request read failed', error, stackTrace, {'id': id});
      throw const InspectionFailure('Could not load that request.');
    }
  }

  // --- Inspector side --------------------------------------------------------

  /// The inspector's job board: requests waiting to be claimed.
  ///
  /// Takes no user id, exactly like [listForClient]. The board RLS policy
  /// (`inspections_select_board`) already restricts rows to `pending` requests
  /// in the caller's `location_city`, so the only predicate written here is the
  /// status the board is for — which also matches the board index in migration
  /// 0001. Passing the inspector's identity as a parameter would be a filter
  /// that is accepted and then ignored, which reads as though the caller decides
  /// whose board this is.
  Future<List<InspectionRequest>> listBoard() async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from(_table)
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      return rows.map(InspectionRequest.fromRow).toList();
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('job board load failed', error, stackTrace);
      throw const InspectionFailure('Could not load the job board.');
    }
  }

  /// The signed-in inspector's own jobs, newest first.
  ///
  /// This one does take a user id, and unlike [listForClient] and [listBoard]
  /// it is used rather than being a redundant echo of RLS. The participant RLS
  /// policy returns rows where the caller is either party — but "my jobs" means
  /// the *inspector* side of those rows. An inspector who also buys cars holds
  /// both roles, and a row where they are the buyer must not appear in their
  /// jobs list, so the query has to say which side. The narrowing cannot be
  /// abused: RLS still refuses any row the caller has no part in, so passing a
  /// stranger's id cannot read their jobs.
  Future<List<InspectionRequest>> listForInspector(String inspectorId) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from(_table)
          .select()
          .eq('inspector_id', inspectorId)
          .order('created_at', ascending: false);

      return rows.map(InspectionRequest.fromRow).toList();
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('inspector jobs load failed', error, stackTrace);
      throw const InspectionFailure('Could not load your jobs.');
    }
  }

  /// Claims a pending request as the calling inspector.
  ///
  /// The `pending -> accepted` transition is what migration 0001's
  /// `enforce_inspection_transition` trigger permits, and the same trigger
  /// binds `inspector_id := auth.uid()` — so an acceptance is always assigned
  /// to the inspector who made it, even if two of them tap Accept at once. What
  /// this method has to handle is the loser of that race: their update matches
  /// zero rows because the request left `pending` a moment earlier. The
  /// `.select().single()` turns that silent no-op into a PGRST116 that the
  /// caller can read as "taken", instead of letting the app cheerfully report
  /// an acceptance the database refused.
  Future<void> accept(String id) async {
    await _transition(id, 'request accept failed', claim: true, status: 'accepted');
  }

  /// Starts an accepted job: `accepted -> in_progress`.
  Future<void> start(String id) async {
    await _transition(id, 'request start failed', claim: false, status: 'in_progress');
  }

  /// Completes an in-progress job: `in_progress -> completed`.
  Future<void> complete(String id) async {
    await _transition(id, 'request complete failed', claim: false, status: 'completed');
  }

  /// The shared shape of the three inspector status writes.
  ///
  /// `claim: true` is the one write where the row can be stolen out from under
  /// the writer (another inspector taking the same pending request), so [accept]
  /// uses it to distinguish "taken by someone else" from "moved on" when the
  /// update matches nothing.
  Future<void> _transition(
    String id,
    String logName, {
    required bool claim,
    required String status,
  }) async {
    try {
      await _client
          .from(_table)
          .update(<String, dynamic>{'status': status})
          .eq('id', id)
          .select()
          .single();
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error(logName, error, stackTrace, {'id': id});
      throw InspectionFailure(_transitionMessageFor(error, claim: claim));
    }
  }

  /// Maps a transition failure onto something an inspector can act on.
  ///
  /// The trigger is the authority on what is legal, and its one failure needs a
  /// sentence that says the request moved on — not [_messageFor]'s "rejected by
  /// the server", which is about form fields and would be true of nothing here.
  String _transitionMessageFor(PostgrestException error, {required bool claim}) {
    if (error.code == 'PGRST116') {
      // The update matched no row: the request is no longer in the state the
      // write assumed it was. For a claim the realistic cause is another
      // inspector getting there first.
      return claim
          ? 'Another inspector just took this request.'
          : 'This request is no longer in that state.';
    }
    if (error.message.toLowerCase().contains('transition')) {
      return 'This action is not allowed for this request right now.';
    }
    return _messageFor(error);
  }

  /// Cancels a request.
  ///
  /// A buyer's only write action in Phase 2. The `cancelled` transition is
  /// enforced by the `enforce_inspection_transition` trigger, so a client
  /// asking for an illegal jump is refused by the database rather than by this
  /// method — the check here is for the error message, not for correctness.
  Future<void> cancel(String id) async {
    try {
      await _client.from(_table).update(<String, dynamic>{
        'status': 'cancelled',
      }).eq('id', id);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('request cancel failed', error, stackTrace);
      throw InspectionFailure(_messageFor(error));
    }
  }

  /// Maps a database error onto something a person can act on.
  String _messageFor(PostgrestException error) {
    AppLogger.instance.debug('inspection error detail', {
      'raw': error.message,
      'code': error.code,
    });

    // A check-constraint violation means the client sent something the schema
    // forbids. The form validates against the same bounds, so reaching this
    // means the two have drifted, and the useful thing to say is that the
    // request was rejected rather than to guess which field.
    if (error.code == '23514') {
      return 'Some details were rejected by the server. Please check them and '
          'try again.';
    }
    if (error.code == '42501') {
      return 'You are not allowed to do that.';
    }
    return 'Something went wrong. Please try again.';
  }
}
