import 'custom_centre.dart';
import 'inspection_bid.dart';

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

  /// True once an inspector holds the job and before it is closed.
  ///
  /// The negotiation window, and narrower than [isOpen] on purpose. `pending` is open
  /// work but belongs to nobody — an inspector countering a job that is still on the
  /// board would be pricing a job another inspector is about to claim, and
  /// `seal_bid` refuses it. `cancelled` is closed. What is left is exactly the two
  /// statuses where an inspector named on the row can change the price, which is what
  /// this is for.
  ///
  /// Deliberately not `isOpen && !isPending`: stated positively so a fifth status
  /// added to the enum has to answer this question instead of inheriting an answer
  /// from a pair of negations that happens to be true.
  bool get isClaimed => switch (this) {
    InspectionStatus.accepted || InspectionStatus.inProgress => true,
    InspectionStatus.pending ||
    InspectionStatus.completed ||
    InspectionStatus.cancelled => false,
  };
}

/// A row of `public.car_inspections` — one request for one car.
///
/// Immutable, and constructed only through [fromRow], so the only place that has
/// to understand PostgREST's decoding quirks is the factory. See [_asDouble] for
/// the one that actually bites.
///
/// [customCentre] is the one field that is not about the car. It is [CustomCentre]
/// rather than an [InspectionCentre] because an unlisted centre has no id, no city
/// of its own and no approved fee — it is a name and a point on the map attached
/// to this one request.
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
    this.customCentre,
    this.platformFee,
    this.inspectorNet,
    this.agreedTotal,
    this.bidStatus = BidStatus.none,
    this.agreedAt,
    this.counterNote,
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

  /// The budget the buyer proposed, inclusive of the platform fee.
  ///
  /// It used to be a figure this codebase computed and the buyer was shown — a
  /// fixed estimate with no input on the form. Migration 0011 gives the column
  /// back its original meaning: it is what the buyer asked to pay, and it is
  /// frozen against them the moment an inspector claims the job, by migration
  /// 0009's rule 2. What the platform's cut of it is, see [platformFee].
  final double price;

  /// The platform's commission on this request, copied from
  /// `platform_settings` when the request was created.
  ///
  /// Nullable because a request filed before migration 0011 has no snapshot.
  /// Read as "not recorded" rather than zero: a zero here would state that the
  /// platform waived its fee on a job it had already priced.
  final double? platformFee;

  /// What the inspector keeps, once the job is claimed.
  ///
  /// Never written by a client — `enforce_bidding` derives it from the budget and
  /// the snapshot, or copies it off an accepted counter-offer. Null until then,
  /// which is what lets the inspector's card show the *offered* earnings rather
  /// than a zero that would read as a commission of the entire budget.
  final double? inspectorNet;

  /// What the buyer pays. Stored rather than derived from [price], because the
  /// invoice is a fact about a transaction rather than a recomputation against a
  /// commission setting that may since have moved.
  final double? agreedTotal;

  /// Where the negotiation has got to. See [BidStatus].
  final BidStatus bidStatus;

  /// When the two sides settled, or when the buyer last refused an offer.
  final DateTime? agreedAt;

  /// The buyer's one line on why they refused, handed back to the inspector on the
  /// next offer form so the second round is not a blind guess.
  final String? counterNote;

  /// The approved centre's own fee, set from `inspection_centres.fee` when the
  /// inspector books it. Null until then, which is what lets the buyer's invoice
  /// show "determined later" rather than a zero that would read as "free".
  final double? centerFee;

  /// The booking the inspector makes during the 48-hour coordination window.
  /// Null while the centre and time are still being agreed.
  final DateTime? appointmentAt;

  /// When the buyer approved the invoice. Null until they press the button.
  final DateTime? clientApprovedAt;

  /// A centre outside the approved list, when one was named.
  ///
  /// Null on every inspection that happens at a centre from `inspection_centres`,
  /// which is the common case. When it is set it is a *suggestion*, not a booking:
  /// the booking is [inspectionCenterName], and an inspector booking this centre
  /// copies its name there so the report, the buyer's invoice and the board all
  /// read the same string without each of them knowing this column exists.
  final CustomCentre? customCentre;

  /// True when someone has named an unlisted centre, whether the buyer suggested
  /// it or the inspector found it.
  bool get hasCustomCentre => customCentre != null;

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

  /// True once an inspector is holding the job, whatever the negotiation says.
  ///
  /// The boundary the bidding rules turn on: an offer is only possible after this,
  /// because before it there is nobody to send one to.
  bool get isClaimed => inspectorId != null;

  /// True while a counter-offer is waiting on the buyer.
  bool get isAwaitingBuyerResponse => bidStatus == BidStatus.pending;

  /// True when the terms could still change, which is when the screens show a
  /// negotiation control at all.
  ///
  /// Excludes `completed` and `cancelled` because those are terminal: migration
  /// 0011's `seal_bid` refuses an offer on a closed inspection, so offering a
  /// button that the database will reject is a worse bug than hiding it.
  bool get isNegotiable =>
      !isAwaitingInspector &&
      status != InspectionStatus.completed &&
      status != InspectionStatus.cancelled;

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
      platformFee: row['platform_fee'] == null ? null : _asDouble(row['platform_fee']),
      inspectorNet: row['inspector_net'] == null ? null : _asDouble(row['inspector_net']),
      agreedTotal: row['agreed_total'] == null ? null : _asDouble(row['agreed_total']),
      bidStatus: BidStatus.fromName(row['bid_status'] as String?),
      agreedAt: _asDate(row['agreed_at']),
      counterNote: row['counter_note'] as String?,
      centerFee: row['center_fee'] == null ? null : _asDouble(row['center_fee']),
      appointmentAt: _asDate(row['appointment_at']),
      clientApprovedAt: _asDate(row['client_approved_at']),
      clientNotes: row['client_notes'] as String?,
      customCentre: _customCentreOf(row),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  /// The custom centre on this row, or null when there is none.
  ///
  /// Built from the triple rather than from whichever columns happen to be present,
  /// so a row that somehow violates migration 0010's shape constraint reads as "no
  /// custom centre" instead of as a centre at (0, 0) in the Gulf of Guinea. The
  /// database refuses to store that shape, so this is defence in depth rather than
  /// a case that occurs.
  static CustomCentre? _customCentreOf(Map<String, dynamic> row) {
    final String? name = row['custom_centre_name'] as String?;
    final num? lat = row['custom_centre_lat'] as num?;
    final num? lng = row['custom_centre_lng'] as num?;
    if (name == null || lat == null || lng == null) return null;
    return CustomCentre(
      name: name,
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      proofPhotoPath: row['custom_centre_proof_photo_url'] as String? ?? '',
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
    double? platformFee,
    double? inspectorNet,
    double? agreedTotal,
    BidStatus? bidStatus,
    DateTime? agreedAt,
    String? counterNote,
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
    CustomCentre? customCentre,
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
    platformFee: platformFee ?? this.platformFee,
    inspectorNet: inspectorNet ?? this.inspectorNet,
    agreedTotal: agreedTotal ?? this.agreedTotal,
    bidStatus: bidStatus ?? this.bidStatus,
    agreedAt: agreedAt ?? this.agreedAt,
    counterNote: counterNote ?? this.counterNote,
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
    customCentre: customCentre ?? this.customCentre,
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
