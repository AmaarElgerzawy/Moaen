/// The lifecycle of a request, mirroring the `inspection_status` enum.
///
/// [InspectionStatus.fromName] falls back to [pending] rather than throwing.
/// An unknown status is a server that has added a value this build predates, and
/// showing a request as "awaiting inspector" is a recoverable inaccuracy.
/// Throwing would take out the whole list, which is worse than one row being
/// labelled imprecisely.
enum InspectionStatus {
  pending,
  accepted,
  inProgress,
  completed,
  cancelled;

  static InspectionStatus fromName(String value) => switch (value) {
    'accepted' => InspectionStatus.accepted,
    'in_progress' => InspectionStatus.inProgress,
    'completed' => InspectionStatus.completed,
    'cancelled' => InspectionStatus.cancelled,
    _ => InspectionStatus.pending,
  };

  String get wireName => switch (this) {
    InspectionStatus.pending => 'pending',
    InspectionStatus.accepted => 'accepted',
    InspectionStatus.inProgress => 'in_progress',
    InspectionStatus.completed => 'completed',
    InspectionStatus.cancelled => 'cancelled',
  };

  /// True while the request is still open work.
  ///
  /// Drives whether the client is still waiting or the transaction has settled.
  /// `cancelled` counts as open: the request still exists and the client can
  /// read it, it simply will not progress.
  bool get isOpen => switch (this) {
    InspectionStatus.pending ||
    InspectionStatus.accepted ||
    InspectionStatus.inProgress => true,
    InspectionStatus.completed || InspectionStatus.cancelled => false,
  };
}

/// A row of `public.car_inspections` — one request for one car.
///
/// Immutable, and constructed only through [fromRow], so the only place that has
/// to understand PostgREST's decoding quirks is the factory. See [_asDouble] for
/// the one that actually bites.
class InspectionRequest {
  const InspectionRequest({
    required this.id,
    required this.referenceNo,
    required this.clientId,
    required this.carMake,
    required this.carModel,
    required this.carYear,
    required this.sellerPhone,
    required this.sellerLocationAddress,
    required this.city,
    required this.status,
    required this.price,
    required this.createdAt,
    required this.updatedAt,
    this.inspectorId,
    this.inspectionCenterName,
    this.clientNotes,
  });

  final String id;

  /// Sequential, assigned by the database. Rendered as `MN-1001`.
  ///
  /// Never taken from the client: migration 0004's trigger overwrites it on
  /// insert and restores it on update, so a value read back from a row is
  /// trustworthy as an identifier to quote.
  final int referenceNo;

  final String clientId;
  final String? inspectorId;
  final String carMake;
  final String carModel;
  final int carYear;
  final String sellerPhone;
  final String sellerLocationAddress;

  /// The city the request is posted in, and the only city whose inspectors see
  /// it. Distinct from where the car is: the buyer asks from Cairo and the
  /// seller may be in Giza, and the job board is scoped by this column because
  /// it is the inspector's service area, not the car's location.
  final String city;

  final String? inspectionCenterName;
  final InspectionStatus status;

  /// The buyer's stated budget, in EGP. Not a quote and not a charge — see D2.
  final double price;

  final String? clientNotes;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The handle a buyer reads out. `MN-1001`.
  String get reference => 'MN-$referenceNo';

  /// `Toyota Corolla 2019`, for list rows where the whole identity has to fit on
  /// one line.
  String get carDescription => '$carMake $carModel $carYear';

  /// True while the request has not been picked up.
  bool get isAwaitingInspector => status == InspectionStatus.pending;

  factory InspectionRequest.fromRow(Map<String, dynamic> row) {
    return InspectionRequest(
      id: row['id'] as String,
      // bigint over JSON arrives as a Dart int. A missing reference_no would
      // mean the column was added without the migration default, so it is read
      // defensively rather than cast.
      referenceNo: (row['reference_no'] as num?)?.toInt() ?? 0,
      clientId: row['client_id'] as String,
      inspectorId: row['inspector_id'] as String?,
      carMake: row['car_make'] as String,
      carModel: row['car_model'] as String,
      carYear: (row['car_year'] as num).toInt(),
      sellerPhone: row['seller_phone'] as String,
      sellerLocationAddress: row['seller_location_address'] as String,
      city: row['city'] as String,
      inspectionCenterName: row['inspection_center_name'] as String?,
      status: InspectionStatus.fromName(row['status'] as String? ?? 'pending'),
      price: _asDouble(row['price']),
      clientNotes: row['client_notes'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  @override
  String toString() => 'InspectionRequest($reference, $carDescription, '
      '${status.wireName})';
}

/// Coerces a `numeric` column to a double.
///
/// `price` is `numeric(12,2)`. PostgREST serialises it as a JSON number, so
/// 500.00 may arrive as `500` and Dart decodes that to an `int` — and
/// `(row['price'] as double)` throws a `TypeError` on the most common possible
/// value. Some PostgREST configurations return numeric as a *string* to avoid
/// float precision loss, so that is handled too. A money column that throws on
/// round numbers is the kind of bug that only appears in production.
double _asDouble(Object? value) => switch (value) {
  null => 0,
  final num n => n.toDouble(),
  final String s => double.tryParse(s) ?? 0,
  _ => 0,
};
