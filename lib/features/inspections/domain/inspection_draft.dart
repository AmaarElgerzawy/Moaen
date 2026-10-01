import 'inspection_request.dart';

/// What the buyer is asked to pay, broken down.
///
/// Deliberately *not* persisted as a breakdown. `car_inspections.price` is a
/// single column holding the buyer's stated budget, and D2 settled that there is
/// no quotes table and no negotiation — so a breakdown shown here is a
/// presentation of one number, not a set of priced line items the database
/// knows about. Presenting it as anything more would be inventing a pricing
/// model the schema does not have.
///
/// The split exists because a buyer deciding whether to proceed needs to see
/// *where* the money goes, not just a total. When a real pricing source exists,
/// this becomes the thing that reads it, and nothing above it has to change.
///
/// The three lines are the design's: the approved centre's fee, the inspector's
/// own fee, and the platform's documentation fee. The centre line is the
/// interesting one — it is genuinely unknown when the request is created, because
/// the centre is chosen by the inspector during the 48-hour coordination window.
/// [centerFee] is therefore nullable and the UI says so, rather than showing a
/// zero that would read as "free".
class CostEstimate {
  const CostEstimate({
    this.centerFee,
    this.inspectorFee = defaultInspectorFee,
    this.platformFee = defaultPlatformFee,
  });

  /// The approved centre's fee, or null while it is still to be determined.
  final double? centerFee;

  /// The inspector's coordination and follow-up fee.
  final double inspectorFee;

  /// The platform's documentation and tracking fee.
  final double platformFee;

  /// True while the centre has not been chosen, so the total is a floor rather
  /// than a quote.
  bool get isCenterFeePending => centerFee == null;

  /// The running total. While the centre fee is pending this is the part the
  /// buyer owes regardless, which is why the create screen labels it "the current
  /// estimated total".
  double get total => (centerFee ?? 0) + inspectorFee + platformFee;

  /// The estimate shown on the create screen, before any inspector is involved.
  static const CostEstimate standard = CostEstimate();

  /// Placeholder fees, in SAR. NOT a price list. Replace with a real source
  /// before launch; see the class doc for why these are display values rather
  /// than stored ones. They live here so that no screen hard-codes a number.
  static const double defaultInspectorFee = 150;
  static const double defaultPlatformFee = 49;

  /// The estimate for a request whose centre has been chosen, used once an
  /// inspector names one.
  static CostEstimate withCenterFee(double fee) =>
      CostEstimate(centerFee: fee);

  /// The currency, as the design writes it after a figure (`499 ر.س`).
  static const String currencySuffix = 'ر.س';

  /// The currency, as the design writes it before a figure (`ر.س 300`).
  static const String currencyPrefix = 'ر.س';

  /// Formats an amount the way the design's cost boxes do: `300 ر.س`.
  static String format(double amount) => '${_digits(amount)} $currencySuffix';

  /// Formats an amount the way the design's stats bar and pills do: `ر.س 300`.
  static String formatPrefixed(double amount) =>
      '$currencyPrefix ${_digits(amount)}';

  /// The figure with a thousands separator, in the style the report uses
  /// (`516,778`). No currency: the odometer reading is not money.
  static String amount(double value) => _digits(value);

  /// A trailing `.00` is dropped so the common whole-amount case does not read
  /// as a precise figure it is not, but a genuine 495.50 is kept.
  static String _digits(double amount) {
    final bool whole = amount == amount.roundToDouble();
    final String fixed = whole
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
    // Group thousands so a four-figure budget reads as one, and a five-digit
    // odometer reading does not.
    final List<String> parts = fixed.split('.');
    final String digits = parts.first;
    final StringBuffer grouped = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
      grouped.write(digits[i]);
    }
    return parts.length == 1
        ? grouped.toString()
        : '${grouped.toString()}.${parts[1]}';
  }
}

/// The create-request form, before it becomes a row.
///
/// A separate type from [InspectionRequest] because the form is allowed to be
/// invalid in ways a row is not: a year that is out of range, a price still being
/// typed. Converting one to the other is the moment validation is enforced, so
/// there is exactly one place where "is this request sendable" is decided.
class InspectionDraft {
  const InspectionDraft({
    this.carMake = '',
    this.carModel = '',
    this.carYear = '',
    this.sellerName = '',
    this.sellerPhone = '',
    this.sellerLocationAddress = '',
    this.city = '',
    this.clientNotes = '',
    this.plateNumber = '',
    this.listingUrl = '',
    this.clientName = '',
  });

  final String carMake;
  final String carModel;
  final String carYear;

  /// The design's seller name. Optional to the database and required by the
  /// form's label, which is the design's business and not the schema's.
  final String sellerName;

  final String sellerPhone;
  final String sellerLocationAddress;
  final String city;
  final String clientNotes;
  final String plateNumber;
  final String listingUrl;

  /// The buyer's display name at the moment the request was filed.
  ///
  /// Passed in rather than read from a profile inside [toRow], because the
  /// domain has no session and the profile may have been renamed since. The
  /// inspector sees this string on the job board, so it is the name the two
  /// parties transacted under — see [InspectionRequest.clientName] for why it is
  /// a copy rather than a join.
  final String clientName;

  int? get year {
    final int? parsed = int.tryParse(carYear.trim());
    if (parsed == null) return null;
    // Mirrors the schema's own bound, so the form and the database agree on what
    // is a car. A car from 1950 is unusual but legal; 2100 is not yet a car.
    if (parsed < 1950 || parsed > 2100) return null;
    return parsed;
  }

  /// The row this draft would create.
  ///
  /// Requires a non-null [year]; the caller validates first, which is why that is
  /// a non-null assertion here rather than a silent default the database would
  /// reject.
  Map<String, dynamic> toRow(String clientId) => <String, dynamic>{
    'client_id': clientId,
    'car_make': carMake.trim(),
    'car_model': carModel.trim(),
    'car_year': year!,
    'seller_phone': sellerPhone.trim(),
    'city': city.trim(),
    // The column is NOT NULL, and the design has replaced the buyer's typed
    // budget with a fixed structure: the inspector's fee and the platform's are
    // known now, and the centre's arrives later. So the row records the estimate
    // the buyer was shown and accepted on the form — which is a fact about what
    // they agreed to, not a number they chose. It is deliberately *not* summed
    // with anything: the buyer's ceiling is the whole total, not a fourth line.
    'price': CostEstimate.standard.total,

    // Everything below is omitted rather than sent empty. `seller_location_
    // address` carries a `char_length between 3 and 400` check, so an empty
    // string would be rejected by the database even though the column is
    // nullable — '' is a value, not an absence. The rest have no such check, and
    // NULL is what the screens read as "not recorded yet".
    if (sellerName.trim().isNotEmpty) 'seller_name': sellerName.trim(),
    if (plateNumber.trim().isNotEmpty) 'plate_number': plateNumber.trim(),
    if (listingUrl.trim().isNotEmpty) 'listing_url': listingUrl.trim(),
    if (sellerLocationAddress.trim().length >= 3)
      'seller_location_address': sellerLocationAddress.trim(),
    if (clientNotes.trim().isNotEmpty) 'client_notes': clientNotes.trim(),

    // Frozen at filing for the inspector's job board. Omitted when unknown,
    // like every other optional column above: a profile with no name is not a
    // request with the name "null".
    if (clientName.trim().isNotEmpty) 'client_name': clientName.trim(),
  };

  InspectionDraft copyWith({
    String? carMake,
    String? carModel,
    String? carYear,
    String? sellerName,
    String? sellerPhone,
    String? sellerLocationAddress,
    String? city,
    String? clientNotes,
    String? plateNumber,
    String? listingUrl,
    String? clientName,
  }) => InspectionDraft(
    carMake: carMake ?? this.carMake,
    carModel: carModel ?? this.carModel,
    carYear: carYear ?? this.carYear,
    sellerName: sellerName ?? this.sellerName,
    sellerPhone: sellerPhone ?? this.sellerPhone,
    sellerLocationAddress: sellerLocationAddress ?? this.sellerLocationAddress,
    city: city ?? this.city,
    clientNotes: clientNotes ?? this.clientNotes,
    plateNumber: plateNumber ?? this.plateNumber,
    listingUrl: listingUrl ?? this.listingUrl,
    clientName: clientName ?? this.clientName,
  );
}
