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

  /// When set, every method throws it. Used to drive the error states.
  final InspectionFailure? failure;

  /// Drafts passed to [create], in order.
  final List<InspectionDraft> createdDrafts = <InspectionDraft>[];

  /// Ids passed to [cancel], in order.
  final List<String> cancelledIds = <String>[];

  /// Set to fail only [create], for testing a submit that fails while reads
  /// still work.
  Object? createFailure;

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

  /// Builds a row the way the database would, including a server-assigned
  /// reference.
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
    carMake: draft.carMake,
    carModel: draft.carModel,
    carYear: draft.year ?? 2020,
    sellerPhone: draft.sellerPhone,
    sellerLocationAddress: draft.sellerLocationAddress,
    city: draft.city,
    status: status,
    price: draft.budgetAmount ?? 0,
    clientNotes: draft.clientNotes.trim().isEmpty ? null : draft.clientNotes.trim(),
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  static InspectionRequest _copyWithStatus(
    InspectionRequest r,
    InspectionStatus status,
  ) => InspectionRequest(
    id: r.id,
    referenceNo: r.referenceNo,
    clientId: r.clientId,
    inspectorId: r.inspectorId,
    carMake: r.carMake,
    carModel: r.carModel,
    carYear: r.carYear,
    sellerPhone: r.sellerPhone,
    sellerLocationAddress: r.sellerLocationAddress,
    city: r.city,
    inspectionCenterName: r.inspectionCenterName,
    status: status,
    price: r.price,
    clientNotes: r.clientNotes,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  );
}

/// A request with sensible defaults, for tests that only care about one field.
InspectionRequest buildRequest({
  String id = 'req-1',
  int referenceNo = 1001,
  String clientId = 'user-1',
  String? inspectorId,
  String make = 'Toyota',
  String model = 'Corolla',
  int year = 2019,
  String phone = '+201000000001',
  String address = '12 Nile Street',
  String city = 'Cairo',
  String? centre,
  InspectionStatus status = InspectionStatus.pending,
  double price = 500,
  String? notes,
}) => InspectionRequest(
  id: id,
  referenceNo: referenceNo,
  clientId: clientId,
  inspectorId: inspectorId,
  carMake: make,
  carModel: model,
  carYear: year,
  sellerPhone: phone,
  sellerLocationAddress: address,
  city: city,
  inspectionCenterName: centre,
  status: status,
  price: price,
  clientNotes: notes,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);
