import 'package:moaen/core/pricing/commission.dart';
import 'package:moaen/features/inspections/data/inspection_repository.dart';
import 'package:moaen/features/inspections/domain/custom_centre.dart';
import 'package:moaen/features/inspections/domain/inspection_bid.dart';
import 'package:moaen/features/inspections/domain/inspection_draft.dart';
import 'package:moaen/features/inspections/domain/inspection_request.dart';
import 'package:moaen/features/inspections/domain/order_filter.dart';

import 'test_client.dart';

/// A buyer's answer to a counter-offer, as the fake recorded it.
///
/// A record rather than three parameters, so a test asserting on it reads as one
/// thing — the answer — rather than three separate columns that happen to have been
/// sent together.
typedef BidAnswer = ({String inspectionId, bool accept, String counterNote});

/// An [InspectionRepository] with no network behind it.
///
/// Subclasses the real repository and overrides every method the app calls, for
/// the same reason `FakeAuthRepository` does: the real class is concrete over
/// `SupabaseClient`, and a widget test needs to control what a read returns and
/// what a write records without a network round trip.
///
/// A fake rather than a mock on purpose: these tests assert on the *rows* a
/// screen ends up showing, so a spy that records calls and returns nothing would
/// let a test pass while the screen rendered an empty list.
class FakeInspectionRepository extends InspectionRepository {
  FakeInspectionRepository({List<InspectionRequest>? requests, this.failure})
    : _requests = <InspectionRequest>[...?requests],
      super(createTestClient());

  /// Mutable, because a test may create a request and then assert the list
  /// screen shows it. `final` would make that impossible without rebuilding the
  /// whole fake.
  final List<InspectionRequest> _requests;

  /// When set, every method throws it. Used to drive the error states. Mutable
  /// so a test can render the error state and then clear it to exercise retry.
  InspectionFailure? failure;

  /// The inspector identity [accept] assigns a request to. Tests must make the
  /// signed-in inspector's auth profile use this id, or the accepted job will
  /// not appear in their jobs list — mirroring how the trigger binds
  /// `inspector_id := auth.uid()` in the real database.
  String assignedInspectorId = 'inspector-1';

  /// Drafts passed to [create], in order.
  final List<InspectionDraft> createdDrafts = <InspectionDraft>[];

  /// Ids passed to [cancel], in order.
  final List<String> cancelledIds = <String>[];

  /// Ids passed to [accept], [start] and [complete], in order.
  final List<String> acceptedIds = <String>[];
  final List<String> startedIds = <String>[];
  final List<String> completedIds = <String>[];

  /// Set to fail only [create], for testing a submit that fails while reads
  /// still work.
  Object? createFailure;

  /// Fail a single inspector transition, for testing a write that fails while
  /// reads still work.
  Object? acceptFailure;
  Object? startFailure;
  Object? completeFailure;

  /// The same, for the two writes the design's booking and approval buttons make.
  Object? bookFailure;
  Object? approveFailure;

  /// Ids passed to [book] and [approveInvoice], in order.
  final List<String> bookedIds = <String>[];
  final List<String> approvedIds = <String>[];

  @override
  Future<List<InspectionRequest>> listForClient() async {
    final InspectionFailure? f = failure;
    if (f != null) throw f;
    return List<InspectionRequest>.of(_requests);
  }

  @override
  Future<InspectionRequest?> latestForClient() async {
    final InspectionFailure? f = failure;
    if (f != null) throw f;

    // Newest first, matching the real query's ordering. Deliberately not
    // filtered to open requests: the dashboard shows the most recent request
    // whatever its status, so a finished report stays reachable.
    return _requests.isEmpty ? null : _requests.first;
  }

  @override
  Future<InspectionRequest> create(
    InspectionDraft draft,
    String clientId,
  ) async {
    createdDrafts.add(draft);
    final Object? f = createFailure;
    if (f != null) throw f;

    final InspectionRequest created = _row(
      id: 'created-${createdDrafts.length}',
      referenceNo: 1000 + createdDrafts.length,
      clientId: clientId,
      draft: draft,
      status: InspectionStatus.pending,
    );
    _requests.add(created);
    return created;
  }

  @override
  Future<InspectionRequest> byId(String id) async {
    final InspectionFailure? f = failure;
    if (f != null) throw f;

    return _requests.firstWhere(
      (InspectionRequest r) => r.id == id,
      orElse: () =>
          throw const InspectionFailure('Could not load that request.'),
    );
  }

  @override
  Future<void> cancel(String id) async {
    cancelledIds.add(id);
    final InspectionFailure? f = failure;
    if (f != null) throw f;

    final int index = _requests.indexWhere((InspectionRequest r) => r.id == id);
    if (index == -1) return;
    _requests[index] = _copyWithStatus(
      _requests[index],
      InspectionStatus.cancelled,
    );
  }

  @override
  Future<List<InspectionRequest>> listBoard() async {
    final InspectionFailure? f = failure;
    if (f != null) throw f;

    // The real board is scoped to the inspector's city by RLS; the fake scopes
    // to the status that board rows have, which is what the screens distinguish.
    return <InspectionRequest>[
      for (final InspectionRequest request in _requests)
        if (request.status == InspectionStatus.pending) request,
    ];
  }

  @override
  Future<List<InspectionRequest>> listForInspector(String inspectorId) async {
    final InspectionFailure? f = failure;
    if (f != null) throw f;

    return <InspectionRequest>[
      for (final InspectionRequest request in _requests)
        if (request.inspectorId == inspectorId) request,
    ];
  }

  /// Every order, filtered the way the database would.
  ///
  /// Modelled rather than stubbed, and it has to be modelled: the orders monitor
  /// renders its status breakdown *below* the row list and only when that list is
  /// non-empty, so a fake that answered an unfiltered read with nothing would make
  /// the breakdown's test pass for the wrong reason — a monitor showing an empty
  /// state rather than a grouped count.
  ///
  /// The filters mirror the repository's own predicates, including the two that are
  /// easy to get wrong from the outside: the free-text term is a *case-insensitive*
  /// substring over the reference, the car and the buyer, and the value floor reads
  /// the agreed total with the budget as the fallback rather than the budget alone.
  @override
  Future<List<InspectionRequest>> listAll({
    OrderFilter filter = OrderFilter.none,
    int limit = 200,
  }) async {
    final InspectionFailure? f = failure;
    if (f != null) throw f;

    final String term = filter.search.trim().toLowerCase();
    final List<InspectionRequest> matched = <InspectionRequest>[
      for (final InspectionRequest request in _requests)
        if (_matches(request, filter, term)) request,
    ];

    // Newest first, and capped — the two things the repository does that a monitor
    // relying on "200 rows is all of them" would otherwise be wrong about.
    matched.sort(
      (InspectionRequest a, InspectionRequest b) =>
          b.createdAt.compareTo(a.createdAt),
    );
    return matched.take(limit).toList();
  }

  static bool _matches(
    InspectionRequest request,
    OrderFilter filter,
    String term,
  ) {
    if (filter.status != null && request.status != filter.status) return false;
    if (filter.city != null &&
        filter.city!.isNotEmpty &&
        request.city != filter.city) {
      return false;
    }
    if (term.isNotEmpty) {
      final String buyer = request.clientName ?? '';
      final bool hit =
          request.referenceNo.toString().contains(term) ||
          request.carMake.toLowerCase().contains(term) ||
          request.carModel.toLowerCase().contains(term) ||
          buyer.toLowerCase().contains(term);
      if (!hit) return false;
    }
    final double? floor = filter.minValue;
    if (floor != null && (request.agreedTotal ?? request.price) < floor) {
      return false;
    }
    if (filter.from != null && request.createdAt.isBefore(filter.from!)) {
      return false;
    }
    if (filter.to != null && request.createdAt.isAfter(filter.to!)) {
      return false;
    }
    return true;
  }

  @override
  Future<void> accept(String id, {String? inspectorName}) async {
    acceptedIds.add(id);
    final Object? claimFailure = acceptFailure;
    if (claimFailure != null) throw claimFailure;
    final InspectionFailure? f = failure;
    if (f != null) throw f;

    final int index = _requests.indexWhere((InspectionRequest r) => r.id == id);
    if (index == -1) return;
    // The trigger binds the claiming inspector; the fake does the same using
    // [assignedInspectorId], and freezes the name the same way the real accept
    // write does.
    final InspectionRequest current = _requests[index];
    final double fee = commission.feeFor(current.price);
    final InspectionRequest claimed = current.copyWith(
      status: InspectionStatus.accepted,
      inspectorId: assignedInspectorId,
      inspectorName: inspectorName,
      platformFee: fee,
      inspectorNet: current.price - fee,
      agreedTotal: current.price,
      // A claim is not a negotiation, so this is written explicitly rather than left
      // to the column default — the same value either way, but stated here because
      // it is a fact about the claim and not about the row.
      bidStatus: BidStatus.none,
    );
    _requests[index] = claimed;
  }

  /// [accept], on a claim, writes the fee/net/total split from [commission] exactly as
  /// `enforce_bidding` does.
  ///
  /// Modelled rather than left null because the inspector's whole earnings card and
  /// the buyer's invoice both read those three columns, and a fake that left them
  /// null would make every screen that depends on a claimed price render its empty
  /// case — so a test would "pass" against a screen no real request can reach.
  Commission commission = const Commission();

  /// Every answer passed to [respondToBid], in order.
  ///
  /// Recorded rather than only applied because the buyer's answer is *one word and a
  /// sentence*. A test asserting only the resulting row would pass against a
  /// repository that quietly wrote the agreed amounts itself — which is exactly the
  /// thing the real write is built so a client cannot do.
  final List<BidAnswer> bidAnswers = <BidAnswer>[];

  /// Thrown by [respondToBid] alone.
  ///
  /// Separate from [failure] because a test for "the answer was refused" needs the
  /// *read* to keep working: if every method threw, the page would render its load
  /// error instead of the offer card, and the test would pass for the wrong reason —
  /// asserting a banner that had nothing to do with the answer.
  Object? respondFailure;

  @override
  Future<void> respondToBid(
    String id, {
    required bool accept,
    String counterNote = '',
  }) async {
    bidAnswers.add((
      inspectionId: id,
      accept: accept,
      counterNote: counterNote.trim(),
    ));
    final Object? answerFailure = respondFailure;
    if (answerFailure != null) throw answerFailure;
    final InspectionFailure? f = failure;
    if (f != null) throw f;

    final int index = _requests.indexWhere((InspectionRequest r) => r.id == id);
    if (index == -1) return;
    // `enforce_bidding` copies the amounts off the open offer. There is no offer here
    // to copy, so only the flag and the note move — which is enough for the screens
    // to stop offering the answer, and is all this fake can honestly claim to know.
    _requests[index] = _requests[index].copyWith(
      bidStatus: accept ? BidStatus.agreed : BidStatus.declined,
      counterNote: counterNote.trim().isEmpty ? null : counterNote.trim(),
    );
  }

  @override
  Future<void> start(String id) async {
    startedIds.add(id);
    final Object? writeFailure = startFailure;
    if (writeFailure != null) throw writeFailure;
    final InspectionFailure? f = failure;
    if (f != null) throw f;

    final int index = _requests.indexWhere((InspectionRequest r) => r.id == id);
    if (index == -1) return;
    _requests[index] = _copyWithStatus(
      _requests[index],
      InspectionStatus.inProgress,
    );
  }

  @override
  Future<void> complete(String id) async {
    completedIds.add(id);
    final Object? writeFailure = completeFailure;
    if (writeFailure != null) throw writeFailure;
    final InspectionFailure? f = failure;
    if (f != null) throw f;

    final int index = _requests.indexWhere((InspectionRequest r) => r.id == id);
    if (index == -1) return;
    _requests[index] = _copyWithStatus(
      _requests[index],
      InspectionStatus.completed,
    );
  }

  @override
  Future<void> book(
    String id, {
    required String centreName,
    required double fee,
    required DateTime appointmentAt,
    CustomCentre? customCentre,
  }) async {
    bookedIds.add(id);
    final Object? writeFailure = bookFailure;
    if (writeFailure != null) throw writeFailure;
    final InspectionFailure? f = failure;
    if (f != null) throw f;

    // Recorded so a test can assert on what the booking form asked for. The
    // custom centre is not written back onto the request the way a real one would
    // be: this fake models the catalogue booking, and folding the custom centre in
    // here would mean a test asserting `centreName` was really asserting on a
    // second, unrelated write.
    lastBookedCentre = customCentre;
    lastBookedFee = fee;

    final int index = _requests.indexWhere((InspectionRequest r) => r.id == id);
    if (index == -1) return;
    _requests[index] = _requests[index].copyWith(
      inspectionCenterName: centreName,
      centerFee: fee,
      appointmentAt: appointmentAt,
    );
  }

  /// The custom centre passed to the most recent [book], or null if the last
  /// booking was at an approved centre.
  CustomCentre? lastBookedCentre;

  /// The fee passed to the most recent [book].
  ///
  /// Recorded separately from the request's `centerFee` so a test can tell the
  /// figure the inspector typed from the one the fake then echoed back.
  double? lastBookedFee;

  @override
  Future<void> approveInvoice(String id) async {
    approvedIds.add(id);
    final Object? writeFailure = approveFailure;
    if (writeFailure != null) throw writeFailure;
    final InspectionFailure? f = failure;
    if (f != null) throw f;

    final int index = _requests.indexWhere((InspectionRequest r) => r.id == id);
    if (index == -1) return;
    // A fixed timestamp rather than `DateTime.now()`, so a test can assert on the
    // exact value instead of a range.
    _requests[index] = _requests[index].copyWith(
      clientApprovedAt: DateTime.utc(2026, 1, 2),
    );
  }

  /// Builds a row the way the database would, including a server-assigned
  /// reference.
  ///
  /// Every field is carried across from the draft, because the fake is the only
  /// thing between a widget test and the real `fromRow` decoding — a field
  /// dropped here is a field no test can ever see a screen render.
  static InspectionRequest _row({
    required String id,
    required int referenceNo,
    required String clientId,
    required InspectionDraft draft,
    required InspectionStatus status,
  }) => InspectionRequest(
    id: id,
    referenceNo: referenceNo,
    clientId: clientId,
    clientName: draft.clientName.trim().isEmpty
        ? null
        : draft.clientName.trim(),
    carMake: draft.carMake,
    carModel: draft.carModel,
    carYear: draft.year ?? 2020,
    sellerName: draft.sellerName.trim().isEmpty
        ? null
        : draft.sellerName.trim(),
    sellerPhone: draft.sellerPhone,
    sellerLocationAddress: draft.sellerLocationAddress,
    city: draft.city,
    plateNumber: draft.plateNumber.trim().isEmpty
        ? null
        : draft.plateNumber.trim(),
    listingUrl: draft.listingUrl.trim().isEmpty
        ? null
        : draft.listingUrl.trim(),
    status: status,
    // The budget the buyer typed, not a platform estimate: `price` is the buyer's
    // proposal, and every later figure — the fee, the inspector's net, the agreed
    // total — is derived from it. A fake that wrote `CostEstimate.standard.total`
    // here would quietly re-flatten a feature the form now collects input for.
    price: draft.budget,
    clientNotes: draft.clientNotes.trim().isEmpty
        ? null
        : draft.clientNotes.trim(),
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  /// The single mutation path, so no test double can be a field short.
  static InspectionRequest _copyWithStatus(
    InspectionRequest r,
    InspectionStatus status,
  ) => r.copyWith(status: status);
}

/// A request with sensible defaults, for tests that only care about one field.
///
/// The claimed-status defaults are the important part: [InspectionStatus.accepted]
/// and [inProgress] mean an inspector holds the job, and the trigger writes the fee,
/// the net and the agreed total at that moment. A builder that left them null for a
/// claimed request would produce a row the database cannot produce, and every screen
/// that reads them would render its "not priced yet" case — so the tests below it
/// would pass against a request no real inspector ever sees. The commission is the
/// one migration 0011 provisions, so the figures are 451/49 on the default 500
/// budget unless a test asks for something else.
InspectionRequest buildRequest({
  String id = 'req-1',
  int referenceNo = 1001,
  String clientId = 'user-1',
  String? clientName,
  String? inspectorId,
  String? inspectorName,
  String make = 'Toyota',
  String model = 'Corolla',
  int year = 2019,
  String? sellerName,
  String phone = '+201000000001',
  String? address = '12 Nile Street',
  String city = 'Dammam',
  String? centre,
  double? centreFee,
  InspectionStatus status = InspectionStatus.pending,
  double price = 500,
  double? platformFee,
  double? inspectorNet,
  double? agreedTotal,
  BidStatus bidStatus = BidStatus.none,
  String? counterNote,
  Commission commission = const Commission(),
  String? notes,
  String? plate,
  String? vin,
  int? odometerKm,
  DateTime? appointmentAt,
  DateTime? clientApprovedAt,
  CustomCentre? customCentre,
}) {
  // The claim-time split, defaulted for a claimed request and computed from the
  // budget. Written as a body rather than folded into the parameter defaults
  // because all three have to agree about one commission, and three independent
  // defaults are three places for them to stop agreeing.
  final bool claimed =
      status == InspectionStatus.accepted ||
      status == InspectionStatus.inProgress;
  final double? fee =
      platformFee ?? (claimed ? commission.feeFor(price) : null);
  final double? net =
      inspectorNet ?? (claimed ? commission.netFor(price) : null);
  final double? total = agreedTotal ?? (claimed ? price : null);

  return InspectionRequest(
    id: id,
    referenceNo: referenceNo,
    clientId: clientId,
    clientName: clientName,
    inspectorId: inspectorId,
    inspectorName: inspectorName,
    carMake: make,
    carModel: model,
    carYear: year,
    sellerName: sellerName,
    sellerPhone: phone,
    sellerLocationAddress: address,
    city: city,
    inspectionCenterName: centre,
    centerFee: centreFee,
    status: status,
    price: price,
    platformFee: fee,
    inspectorNet: net,
    agreedTotal: total,
    bidStatus: bidStatus,
    counterNote: counterNote,
    clientNotes: notes,
    plateNumber: plate,
    vin: vin,
    odometerKm: odometerKm,
    appointmentAt: appointmentAt,
    clientApprovedAt: clientApprovedAt,
    customCentre: customCentre,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}
