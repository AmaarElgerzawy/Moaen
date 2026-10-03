import 'package:moaen/core/pricing/commission.dart';
import 'package:moaen/features/inspections/data/bid_repository.dart';
import 'package:moaen/features/inspections/data/inspection_repository.dart';
import 'package:moaen/features/inspections/domain/inspection_bid.dart';

import 'test_client.dart';

/// A [BidRepository] with no network behind it.
///
/// Models the two things the real `seal_bid` trigger does that a client cannot do
/// for itself, because both of them are the reason this fake exists:
///
///  * it assigns the round, the fee snapshot and the total, so a test can never
///    accidentally *pass* by having set them itself — [InspectionBid.toInsertRow] is
///    the whole of what the real client sends, and it has none of those columns;
///  * a second offer supersedes the first rather than stacking beside it.
///
/// An inspector id, so the sealed offer has one, since the trigger binds it to
/// `auth.uid()`.
class FakeBidRepository extends BidRepository {
  FakeBidRepository({this.inspectorId = 'inspector-1'})
    : super(createTestClient());

  final String inspectorId;

  /// Offers per inspection, newest round first, as the real read returns them.
  final Map<String, List<InspectionBid>> offersByInspection =
      <String, List<InspectionBid>>{};

  /// Every insert that reached the repository, in order.
  final List<Map<String, dynamic>> inserts = <Map<String, dynamic>>[];

  /// Thrown by every method when set. Drives the two error states on both sides.
  InspectionFailure? failure;

  /// The commission this fake seals offers with.
  ///
  /// Matches the row migration 0011 provisions, so a test that never sets it sees the
  /// figures the database would produce: a 200 net under a 49 fixed fee is a 249 total.
  Commission commission = const Commission();

  /// Seeds an offer without going through [submit].
  ///
  /// For the buyer-side tests, which need an offer already standing before the card
  /// under test is built. The round and amounts are given rather than derived so a
  /// test can stage a *second* round, which is the only way to reach the "buyer
  /// refused the first one" path.
  InspectionBid seed(
    String inspectionId, {
    required double net,
    double? fee,
    int round = 1,
    BidStatus status = BidStatus.pending,
    String note = '',
  }) {
    final double appliedFee = fee ?? commission.feeFor(net + 49);
    final InspectionBid offer = InspectionBid(
      id: 'bid-$inspectionId-$round',
      inspectionId: inspectionId,
      inspectorId: inspectorId,
      netAmount: net,
      platformFee: appliedFee,
      totalAmount: net + appliedFee,
      round: round,
      status: status,
      note: note,
      createdAt: DateTime.utc(2026, 1, round),
    );
    offersByInspection
        .putIfAbsent(inspectionId, () => <InspectionBid>[])
        .insert(0, offer);
    return offer;
  }

  @override
  Future<List<InspectionBid>> listForInspection(String inspectionId) async {
    final InspectionFailure? f = failure;
    if (f != null) throw f;
    return List<InspectionBid>.of(
      offersByInspection[inspectionId] ?? const <InspectionBid>[],
    );
  }

  @override
  Future<InspectionBid> submit({
    required String inspectionId,
    required double netAmount,
    String note = '',
  }) async {
    inserts.add(<String, dynamic>{
      'inspection_id': inspectionId,
      'net_amount': netAmount,
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
    final InspectionFailure? f = failure;
    if (f != null) throw f;

    final List<InspectionBid> existing = offersByInspection.putIfAbsent(
      inspectionId,
      () => <InspectionBid>[],
    );

    // `seal_bid` supersedes whatever was pending. A pending row that stayed pending
    // would leave two open offers and a buyer card with two answers to give, which is
    // the state the trigger exists to make impossible.
    for (final InspectionBid prior in existing) {
      if (prior.isOpen) {
        final int index = existing.indexOf(prior);
        existing[index] = InspectionBid(
          id: prior.id,
          inspectionId: prior.inspectionId,
          inspectorId: prior.inspectorId,
          netAmount: prior.netAmount,
          platformFee: prior.platformFee,
          totalAmount: prior.totalAmount,
          round: prior.round,
          status: BidStatus.declined,
          note: prior.note,
          createdAt: prior.createdAt,
        );
      }
    }

    // The next round after the highest one seen, not the number of offers: a round is
    // an attempt, and an attempt that was refused still counted.
    final int round =
        existing.fold<int>(
          1,
          (int highest, InspectionBid b) =>
              b.round > highest ? b.round : highest,
        ) +
        1;
    final double fee = commission.feeFor(netAmount);
    final InspectionBid offer = InspectionBid(
      id: 'bid-$inspectionId-$round',
      inspectionId: inspectionId,
      inspectorId: inspectorId,
      netAmount: netAmount,
      platformFee: fee,
      totalAmount: netAmount + fee,
      round: round,
      status: BidStatus.pending,
      note: note.trim(),
      createdAt: DateTime.utc(2026, 2, round),
    );
    existing.insert(0, offer);
    return offer;
  }
}
