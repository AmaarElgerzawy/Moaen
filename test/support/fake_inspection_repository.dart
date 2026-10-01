import 'package:moaen/features/inspections/data/inspection_repository.dart';
import 'package:moaen/features/inspections/domain/inspection_draft.dart';
import 'package:moaen/features/inspections/domain/inspection_request.dart';

import 'test_client.dart';

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
  Future<InspectionRequest> create(InspectionDraft draft, String clientId) async {
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
      orElse: () => throw const InspectionFailure('Could not load that request.'),
    );
  }

  @override
  Future<void> cancel(String id) async {
    cancelledIds.add(id);
    final InspectionFailure? f = failure;
    if (f != null) throw f;

    final int index = _requests.indexWhere((InspectionRequest r) => r.id == id);
    if (index == -1) return;
    _requests[index] = _copyWithStatus(_requests[index], InspectionStatus.cancelled);
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
    final InspectionRequest claimed = _requests[index].copyWith(
      status: InspectionStatus.accepted,
      inspectorId: assignedInspectorId,
      inspectorName: inspectorName,
    );
    _requests[index] = claimed;
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
    _requests[index] = _copyWithStatus(_requests[index], InspectionStatus.inProgress);
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
    _requests[index] = _copyWithStatus(_requests[index], InspectionStatus.completed);
  }

  @override
  Future<void> book(
    String id, {
    required String centreName,
    required double fee,
    required DateTime appointmentAt,
  }) async {
    bookedIds.add(id);
    final Object? writeFailure = bookFailure;
    if (writeFailure != null) throw writeFailure;
    final InspectionFailure? f = failure;
    if (f != null) throw f;

    final int index = _requests.indexWhere((InspectionRequest r) => r.id == id);
    if (index == -1) return;
    _requests[index] = _requests[index].copyWith(
      inspectionCenterName: centreName,
      centerFee: fee,
      appointmentAt: appointmentAt,
    );
  }

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
    clientName: draft.clientName.trim().isEmpty ? null : draft.clientName.trim(),
    carMake: draft.carMake,
    carModel: draft.carModel,
    carYear: draft.year ?? 2020,
    sellerName: draft.sellerName.trim().isEmpty ? null : draft.sellerName.trim(),
    sellerPhone: draft.sellerPhone,
    sellerLocationAddress: draft.sellerLocationAddress,
    city: draft.city,
    plateNumber: draft.plateNumber.trim().isEmpty ? null : draft.plateNumber.trim(),
    listingUrl: draft.listingUrl.trim().isEmpty ? null : draft.listingUrl.trim(),
    status: status,
    // What the form's estimate became, not a figure the buyer chose — the design
    // has no budget input, and the real write sends `CostEstimate.standard.total`.
    price: CostEstimate.standard.total,
    clientNotes: draft.clientNotes.trim().isEmpty ? null : draft.clientNotes.trim(),
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
  String? notes,
  String? plate,
  String? vin,
  int? odometerKm,
  DateTime? appointmentAt,
  DateTime? clientApprovedAt,
}) => InspectionRequest(
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
  clientNotes: notes,
  plateNumber: plate,
  vin: vin,
  odometerKm: odometerKm,
  appointmentAt: appointmentAt,
  clientApprovedAt: clientApprovedAt,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);
