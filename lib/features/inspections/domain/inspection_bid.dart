import 'inspection_draft.dart';
import 'inspection_request.dart';

/// Where an inspection's price has got to.
///
/// Mirrors the `bid_status` enum from migration 0011, and — as everywhere in this
/// codebase — an unknown value falls back rather than throwing, so a column that
/// has grown a fourth state cannot crash the one screen that happens to be open.
enum BidStatus {
  /// Nobody has negotiated. A claimed job at this point is settled at the
  /// buyer's posted budget.
  none,

  /// The assigned inspector has offered a different amount and the buyer has not
  /// answered.
  pending,

  /// Settled, either at the buyer's budget or at an accepted counter-offer.
  agreed,

  /// The buyer refused the offer. The job stays claimed and the inspector may
  /// submit another.
  declined;

  static BidStatus fromName(String? value) => BidStatus.values.firstWhere(
    (BidStatus status) => status.name == value,
    orElse: () => BidStatus.none,
  );
}

/// One counter-offer on one inspection.
///
/// A *net* amount. The inspector quotes what they keep and never what the buyer
/// pays, because the commission is the platform's business and an inspector who
/// can see it will argue about it instead of doing the work.
class InspectionBid {
  const InspectionBid({
    required this.id,
    required this.inspectionId,
    required this.inspectorId,
    required this.netAmount,
    required this.platformFee,
    required this.totalAmount,
    required this.round,
    required this.status,
    this.note = '',
    this.createdAt,
    this.respondedAt,
  });

  factory InspectionBid.fromRow(Map<String, dynamic> row) => InspectionBid(
    id: row['id'] as String,
    inspectionId: row['inspection_id'] as String,
    inspectorId: row['inspector_id'] as String,
    netAmount: _asDouble(row['net_amount']),
    platformFee: _asDouble(row['platform_fee']),
    totalAmount: _asDouble(row['total_amount']),
    round: (row['round'] as num?)?.toInt() ?? 1,
    status: BidStatus.fromName(row['status'] as String?),
    note: row['note'] as String? ?? '',
    createdAt: row['created_at'] == null
        ? null
        : DateTime.parse(row['created_at'] as String),
    respondedAt: row['responded_at'] == null
        ? null
        : DateTime.parse(row['responded_at'] as String),
  );

  final String id;
  final String inspectionId;
  final String inspectorId;

  /// What the inspector keeps, after the platform fee.
  final double netAmount;

  /// The commission that applied when this offer was made.
  ///
  /// Copied onto the offer so it reads the same years later whatever the
  /// commission is set to now. Same reasoning as `platform_fee` on the
  /// inspection, one level down.
  final double platformFee;

  /// What the buyer would pay. `netAmount + platformFee`, filled in by the
  /// database's `seal_bid` rather than by the client — the inspector should not
  /// be asked to do the arithmetic twice, and a client that could set it could
  /// quote a total that does not match its own net.
  final double totalAmount;

  /// The attempt number. Two after a refusal, and so on.
  final int round;

  final BidStatus status;

  /// One line from the inspector. Empty rather than null, because the column is
  /// nullable and "no note" reads as absent on a screen that always shows the
  /// field.
  final String note;

  final DateTime? createdAt;
  final DateTime? respondedAt;

  bool get isOpen => status == BidStatus.pending;

  /// The offer the buyer is being asked about, or null when there is nothing
  /// outstanding.
  ///
  /// Takes a list rather than being a field, because the buyer's screen receives
  /// the inspection and *then* fetches the offers — and it needs the open one out
  /// of a history that also holds the refused rounds, not the first row.
  static InspectionBid? openOffer(List<InspectionBid> bids) {
    for (final InspectionBid bid in bids) {
      if (bid.isOpen) return bid;
    }
    return null;
  }

  /// The column map an insert sends.
  ///
  /// Only what the client is allowed to send. `total_amount`, `platform_fee`,
  /// `round`, `status` and `inspector_id` are all assigned by `seal_bid`: five
  /// fields the inspector must not be able to choose, one trigger, and no
  /// argument about it afterwards.
  Map<String, dynamic> toInsertRow({required String inspectionId}) =>
      <String, dynamic>{
        'inspection_id': inspectionId,
        'net_amount': netAmount,
        if (note.trim().isNotEmpty) 'note': note.trim(),
      };

  static double _asDouble(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse('$value') ?? 0;
}

/// What the two sides can agree on, derived from one inspection and its offers.
///
/// The bidding arithmetic lives here rather than in the three screens that show
/// it, because the three must not be able to disagree: the buyer's invoice, the
/// inspector's earnings line and the offer sheet all read this one object, so a
/// change to the formula cannot leave one of them quoting a different total.
class BidSummary {
  const BidSummary({
    required this.budget,
    required this.platformFee,
    required this.inspectorNet,
    required this.agreedTotal,
    required this.status,
    this.openOffer,
    this.centreFee,
  });

  factory BidSummary.of(
    InspectionRequest request, {
    List<InspectionBid> offers = const <InspectionBid>[],
  }) => BidSummary(
    budget: request.price,
    // A row filed before migration 0011 has no snapshot. The design's standing
    // figure is what those rows were priced with, so quoting it is more accurate
    // than quoting zero — a zero would state that the platform waived its fee on a
    // job it had already taken, and would then hand the whole budget to the
    // inspector as "earnings".
    platformFee: request.platformFee ?? CostEstimate.defaultPlatformFee,
    inspectorNet: request.inspectorNet,
    agreedTotal: request.agreedTotal,
    status: request.bidStatus,
    openOffer: InspectionBid.openOffer(offers),
    centreFee: request.centerFee,
  );

  /// The buyer's ceiling, inclusive of the platform fee.
  final double budget;

  /// The commission snapshotted onto the inspection at creation.
  final double platformFee;

  /// What the inspector keeps, null until the job is claimed.
  final double? inspectorNet;

  /// What the buyer pays, null until the job is claimed.
  final double? agreedTotal;

  final BidStatus status;
  final InspectionBid? openOffer;
  final double? centreFee;

  /// True while the inspector has a figure the buyer has not answered.
  bool get hasOpenOffer => openOffer != null;

  /// What the inspector would keep if they accepted the posted budget right now.
  ///
  /// Never negative, which is the invariant the database enforces with
  /// `least(fee, total)` and a `>= 0` check. Clamped here as well because this is
  /// what a number on a card is derived from, and a card showing a negative
  /// earnings figure would be worse than the database being wrong.
  double get defaultNet => budget - platformFee < 0 ? 0 : budget - platformFee;

  /// The buyer's total for the open offer, falling back to the budget when there
  /// is no offer outstanding.
  double get buyerTotal => openOffer?.totalAmount ?? agreedTotal ?? budget;
}