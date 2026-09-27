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
