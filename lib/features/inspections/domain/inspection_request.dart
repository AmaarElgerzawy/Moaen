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
    this.inspectorName,
    required this.city,
    required this.status,
    required this.price,
    required this.createdAt,
    required this.updatedAt,
    this.sellerLocationAddress,
    this.inspectorId,
    this.inspectionCenterName,
    this.clientNotes,
    this.sellerName,
    this.clientName,
    this.plateNumber,
    this.listingUrl,
    this.vin,
    this.odometerKm,
    this.appointmentAt,
    this.centerFee,
    this.clientApprovedAt,
  });

  final String id;

  /// Sequential, assigned by the database. Rendered as `MN-1001`.
  ///
  /// Never taken from the client: migration 0004's trigger overwrites it on
  /// insert and restores it on update, so a value read back from a row is
  /// trustworthy as an identifier to quote.
  final int referenceNo;

  final String clientId;

  /// The buyer's display name, copied onto the request when it was filed and
  /// frozen there by the transition trigger alongside `seller_name`.
  ///
  /// A copy rather than a join, and not for performance. The design's market card
  /// reads `طالب الفحص: سعود`, but the buyer's name lives in `public.users`, whose
  /// RLS policy lets an inspector read only their own row. Postgres has no
  /// column-level RLS, so making the name reachable would also make the buyer's
  /// email and phone reachable — which is a far larger disclosure than the design
  /// asks for. The frozen copy is also the more honest record: it is the name the
  /// two parties transacted under.
  ///
  /// Null for requests filed before migration 0009 added the column. The board
  /// then shows nothing rather than a placeholder, because "not recorded" is what
  /// the database actually knows.
  final String? clientName;

  final String? inspectorId;

  /// The claiming inspector's name, frozen when they claimed the job.
  ///
  /// Needed for the A4 report, which names the person the verdict stands behind,
  /// and frozen rather than joined for the same reason as [clientName] in the
  /// other direction: `public.users` RLS lets a client read only their own row, so
  /// the buyer the report is written for cannot look the name up. Migration 0009
  /// adds the column and its trigger rejects a write from anyone who is the
  /// client, so this is the only name the report can cite.
  final String? inspectorName;

  final String carMake;
  final String carModel;
  final int carYear;
  final String sellerPhone;

  /// Null when nobody recorded one. The create form has no address input — the
  /// city is the scope — and migration 0007 relaxed the column to match, so
  /// "not recorded" is the normal state rather than an omission.
  final String? sellerLocationAddress;

  /// The design's `👤 بيانات البائع للتنسيق الفوري` name, as distinct from the
  /// buyer who filed the request. Shown to the inspector in the contact box.
  final String? sellerName;

  /// The design's optional plate and listing link. Both optional in the design,
  /// so both are optional here and neither is ever shown as a blank field.
  final String? plateNumber;
  final String? listingUrl;

  /// Read off the car at the centre and printed on the A4 report. Null until an
  /// inspector records it, which is honestly "not read off the car yet".
  final String? vin;

  /// The odometer reading in kilometres, as the report prints it. Null until
  /// read at the centre.
  final int? odometerKm;

  /// The city the request is posted in, and the only city whose inspectors see
  /// it. Distinct from where the car is: the buyer asks from Dammam and the
  /// seller may be in Jeddah, and the job board is scoped by this column because
  /// it is the inspector's service area, not the car's location.
  final String city;

  final String? inspectionCenterName;
  final InspectionStatus status;

  /// The cost structure the buyer approved when they submitted the request.
  ///
  /// It used to be a budget the buyer typed. The design has no budget input: the
  /// fees are fixed (the inspector's 150, the platform's 49) and the centre's
  /// fee arrives later, chosen by the inspector. What the column now holds is
  /// therefore the estimate the buyer was shown and accepted — not a number they
  /// chose, and not a charge. See `InspectionDraft.toRow`.
  final double price;

  /// The approved centre's own fee, set from `inspection_centres.fee` when the
  /// inspector books it. Null until then, which is what lets the buyer's invoice
  /// show "determined later" rather than a zero that would read as "free".
  final double? centerFee;

  /// The booking the inspector makes during the 48-hour coordination window.
  /// Null while the centre and time are still being agreed.
  final DateTime? appointmentAt;

  /// When the buyer approved the invoice. Null until they press the button.
  final DateTime? clientApprovedAt;

  final String? clientNotes;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The handle a buyer reads out. `MN-1001`.
  String get reference => 'MN-$referenceNo';

  /// `تويوتا أف جي (2023)`, for the cards and the report's vehicle tile.
  ///
  /// The year is in parentheses because the design puts it in parentheses in
  /// every one of the six places it writes the car, and a car written
  /// `تويوتا أف جي 2023` in one of them is not the same string as the other five.
  String get carDescription => '$carMake $carModel ($carYear)';

  /// True when the centre is booked, which is what turns the buyer's invoice
  /// from an estimate into a figure with three real lines in it.
  bool get hasBooking =>
      appointmentAt != null && inspectionCenterName != null;

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
      clientName: row['client_name'] as String?,
      inspectorId: row['inspector_id'] as String?,
      inspectorName: row['inspector_name'] as String?,
      carMake: row['car_make'] as String,
      carModel: row['car_model'] as String,
      carYear: (row['car_year'] as num).toInt(),
      sellerPhone: row['seller_phone'] as String,
      sellerLocationAddress: row['seller_location_address'] as String?,
      sellerName: row['seller_name'] as String?,
      plateNumber: row['plate_number'] as String?,
      listingUrl: row['listing_url'] as String?,
      vin: row['vin'] as String?,
      odometerKm: (row['odometer_km'] as num?)?.toInt(),
      city: row['city'] as String,
      inspectionCenterName: row['inspection_center_name'] as String?,
      status: InspectionStatus.fromName(row['status'] as String? ?? 'pending'),
      price: _asDouble(row['price']),
      centerFee: row['center_fee'] == null ? null : _asDouble(row['center_fee']),
      appointmentAt: _asDate(row['appointment_at']),
      clientApprovedAt: _asDate(row['client_approved_at']),
      clientNotes: row['client_notes'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  @override
  String toString() => 'InspectionRequest($reference, $carDescription, '
      '${status.wireName})';

  /// A copy with the given fields replaced; an absent field keeps its value.
  ///
  /// Null means "unchanged" rather than "clear", so this cannot empty a nullable
  /// column. That is the right trade here: this exists for the report, which folds
  /// a resolved centre back into the request, and for tests that move a status.
  /// Neither needs to unset anything, and a `clear` set on a twenty-field
  /// `copyWith` would be machinery no caller uses.
  InspectionRequest copyWith({
    String? id,
    int? referenceNo,
    String? clientId,
    String? clientName,
    String? inspectorId,
    String? inspectorName,
    String? carMake,
    String? carModel,
    int? carYear,
    String? sellerPhone,
    String? sellerLocationAddress,
    String? city,
    String? inspectionCenterName,
    InspectionStatus? status,
    double? price,
    double? centerFee,
    DateTime? appointmentAt,
    DateTime? clientApprovedAt,
    String? clientNotes,
    String? sellerName,
    String? plateNumber,
    String? listingUrl,
    String? vin,
    int? odometerKm,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => InspectionRequest(
    id: id ?? this.id,
    referenceNo: referenceNo ?? this.referenceNo,
    clientId: clientId ?? this.clientId,
    clientName: clientName ?? this.clientName,
    inspectorId: inspectorId ?? this.inspectorId,
    inspectorName: inspectorName ?? this.inspectorName,
    carMake: carMake ?? this.carMake,
    carModel: carModel ?? this.carModel,
    carYear: carYear ?? this.carYear,
    sellerPhone: sellerPhone ?? this.sellerPhone,
    sellerLocationAddress: sellerLocationAddress ?? this.sellerLocationAddress,
    city: city ?? this.city,
    inspectionCenterName: inspectionCenterName ?? this.inspectionCenterName,
    status: status ?? this.status,
    price: price ?? this.price,
    centerFee: centerFee ?? this.centerFee,
    appointmentAt: appointmentAt ?? this.appointmentAt,
    clientApprovedAt: clientApprovedAt ?? this.clientApprovedAt,
    clientNotes: clientNotes ?? this.clientNotes,
    sellerName: sellerName ?? this.sellerName,
    plateNumber: plateNumber ?? this.plateNumber,
    listingUrl: listingUrl ?? this.listingUrl,
    vin: vin ?? this.vin,
    odometerKm: odometerKm ?? this.odometerKm,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// Coerces a `timestamptz` to a local [DateTime].
///
/// PostgREST returns these as an ISO-8601 string with an offset. `DateTime.parse`
/// handles both, so the only question is what happens when the column is NULL —
/// which is the normal state for a request that has not been booked yet, and
/// which `!` would turn into a crash on the buyer's home screen.
DateTime? _asDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value as String);
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
