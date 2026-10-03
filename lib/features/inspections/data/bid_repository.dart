import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/inspection_bid.dart';
import 'inspection_repository.dart' show InspectionFailure, InspectionFailureReason;

/// Reads and writes `public.inspection_bids`.
///
/// Separate from [InspectionRepository] because it is a different question with a
/// different audience, in the same way `CentreRepository` is: the offers on one
/// job are read by exactly two people and written by one of them, and folding them
/// into the inspections repository would mean the buyer fetching every offer on
/// every inspection list they ever open.
///
/// Insert-only from the client's point of view, which is the important property.
/// The client sends a net and a note; `platform_fee`, `total_amount`, `round`,
/// `status` and `inspector_id` are all assigned by the database's `seal_bid`
/// trigger. There is no `respondTo` here either — answering an offer is a write of
/// one word to the *inspection*, and `InspectionRepository.respondToBid` owns it,
/// because the trigger that turns that word into the agreed amounts is the same
/// one that enforces the platform fee.
class BidRepository {
  BidRepository(this._client);

  final SupabaseClient _client;

  static const String _table = 'inspection_bids';

  /// Every offer on [inspectionId], newest round first.
  ///
  /// Ordered by round rather than by time because round is what the two sides talk
  /// about — "that's your second offer" — and two offers made in the same minute
  /// would otherwise order arbitrarily.
  ///
  /// Falls back to an empty list rather than throwing when there are none. RLS
  /// makes "no rows" indistinguishable from "no permission" at this layer, and
  /// treating a buyer's first look at a job with no offers as a network failure
  /// would show them an error over a screen that is perfectly fine.
  Future<List<InspectionBid>> listForInspection(String inspectionId) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from(_table)
          .select()
          .eq('inspection_id', inspectionId)
          .order('round', ascending: false);

      return rows.map(InspectionBid.fromRow).toList();
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('offer list failed', error, stackTrace, {
        'inspection_id': inspectionId,
      });
      throw const InspectionFailure('Could not load the offers.');
    }
  }

  /// Submits a counter-offer of [netAmount] on [inspectionId].
  ///
  /// [netAmount] is what the inspector keeps. The buyer's total is computed by the
  /// database and never sent, for the reason in the class doc: an inspector who can
  /// set the total can quote a total that does not match their own net, and then
  /// the two numbers on the buyer's screen stop agreeing with each other.
  ///
  /// Returns the offer as the database sealed it, so the caller shows the real
  /// round number and total rather than the ones it hoped for.
  Future<InspectionBid> submit({
    required String inspectionId,
    required double netAmount,
    String note = '',
  }) async {
    try {
      final Map<String, dynamic> row = await _client
          .from(_table)
          .insert(<String, dynamic>{
            'inspection_id': inspectionId,
            'net_amount': netAmount,
            if (note.trim().isNotEmpty) 'note': note.trim(),
          })
          .select()
          .single();

      return InspectionBid.fromRow(row);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('offer submit failed', error, stackTrace, {
        'inspection_id': inspectionId,
        'net_amount': netAmount,
      });
      final InspectionFailureReason reason = reasonFor(error);
      throw InspectionFailure(
        messageFor(reason),
        reason: reason,
        detail: error.message,
      );
    }
  }

  /// Turns a database refusal into a reason a screen can say something about.
  ///
  /// A [InspectionFailureReason] rather than a sentence, for the reason every other
  /// repository in this codebase does it: the words come from the ARB files, so an
  /// inspector whose offer is refused is told why in their own language instead of
  /// reading a sentence written in the only language this file can produce. What the
  /// mapping buys is that an inspector who offers on a job somebody else already
  /// claimed is told *that*, rather than being shown the same "try again" banner as a
  /// dropped connection.
  static InspectionFailureReason reasonFor(PostgrestException error) {
    final String text = error.message;
    if (text.contains('only the inspector holding this job')) {
      return InspectionFailureReason.notTheAssignedInspector;
    }
    if (text.contains('once the job has been claimed')) {
      return InspectionFailureReason.notYetClaimed;
    }
    if (text.contains('this inspection is closed')) {
      return InspectionFailureReason.inspectionClosed;
    }
    if (text.contains('inspection_bids_net_amount_check')) {
      return InspectionFailureReason.amountOutOfRange;
    }
    return InspectionFailureReason.network;
  }

  /// The English sentence for a reason, for the log and for tests.
  ///
  /// Never rendered — `localizedOfferFailure` in the presentation layer is. Kept
  /// beside [reasonFor] so the two cannot drift: the switch here is the one place that
  /// knows what each reason *means*, and the ARB copy is a translation of it rather
  /// than an independent guess.
  static String messageFor(InspectionFailureReason reason) => switch (reason) {
    InspectionFailureReason.notTheAssignedInspector =>
      'That job belongs to another inspector.',
    InspectionFailureReason.notYetClaimed => 'Claim the job before making an offer.',
    InspectionFailureReason.inspectionClosed => 'This inspection is finished.',
    InspectionFailureReason.amountOutOfRange => 'Enter an amount greater than zero.',
    InspectionFailureReason.noOfferToRespondTo => 'That offer is no longer open.',
    InspectionFailureReason.network || InspectionFailureReason.unknown =>
      'Could not submit the offer. Please try again.',
  };
}