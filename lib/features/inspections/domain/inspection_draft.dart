import 'custom_centre.dart';
import 'inspection_request.dart';

/// What the buyer is asked to pay, broken down.
///
/// Deliberately *not* persisted as a breakdown. `car_inspections.price` holds
/// one number — the buyer's budget — and migration 0011 settles that there is no
/// quotes table; so a breakdown shown here is a presentation of figures the
/// database already stores elsewhere, not a set of priced line items it knows
/// nothing about. Presenting it as anything more would be inventing a pricing
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
///
/// Read from a real inspection through [ofRequest] wherever one is available.
/// The constructor's defaults are display placeholders for the create screen and
/// for rows filed before migration 0011; see [defaultPlatformFee] for why they
/// are constants and not a price list.
class CostEstimate {
  const CostEstimate({
    this.centerFee,
    this.inspectorFee = defaultInspectorFee,
    this.platformFee = defaultPlatformFee,
  });

  /// The breakdown of a request whose own columns record every line.
  ///
  /// This is the factory the three money screens use. The inspector's line is
  /// `inspector_net` — what they actually keep, after the commission — rather
  /// than a constant that would have to be kept in step with it, and the
  /// platform's line is the snapshot on the row rather than today's setting.
  ///
  /// Falls back to the constants where a row predates migration 0011 and carries no
  /// snapshot. That fallback is deliberate: those rows were priced with exactly
  /// those numbers, so quoting them is more accurate than quoting zero, and a zero
  /// would state that the platform waived its fee on a job it had already taken.
  factory CostEstimate.ofRequest(InspectionRequest request) => CostEstimate(
    centerFee: request.centerFee,
    inspectorFee: request.inspectorNet ?? defaultInspectorFee,
    platformFee: request.platformFee ?? defaultPlatformFee,
  );

  /// The approved centre's fee, or null while it is still to be determined.
  final double? centerFee;

  /// The inspector's coordination and follow-up fee.
  final double inspectorFee;

  /// The platform's documentation and tracking fee.
  final double platformFee;

  /// True while the centre has not been chosen, so the total is a floor rather
  /// than a quote.
  bool get isCenterFeePending => centerFee == null;

  /// The running total.
  ///
  /// While the centre fee is pending this is the part the buyer owes regardless,
  /// which is why the create screen labels it "the current estimated total".
  double get total => (centerFee ?? 0) + inspectorFee + platformFee;

  /// The estimate shown on the create screen, before any inspector is involved.
  ///
  /// Only for the create form, where there is no request to read a real figure
  /// from. Everything that already has an inspection should use
  /// [CostEstimate.ofRequest] instead, or it will be quoting the design's
  /// placeholders for a job priced against a real commission.
  static const CostEstimate standard = CostEstimate();

  /// Placeholder fees, in SAR. NOT a price list.
  ///
  /// The platform's figure is superseded by `platform_settings` in migration 0011
  /// and these constants only describe rows filed before that. The inspector's
  /// standing fee is superseded by the budget the buyer posts, so what an
  /// inspector keeps is now an outcome rather than a rate.
  ///
  /// They survive because the create screen has no request yet — the commission is
  /// read live from `platform_settings` there too, but the fallback when that read
  /// fails is this number, and a screen that refuses to render without the network
  /// is worse than one that shows a stale default.
  static const double defaultInspectorFee = 150;
  static const double defaultPlatformFee = 49;

  /// The lowest budget a buyer may post.
  ///
  /// Enforced here as well as by the form so a caller that builds a draft
  /// programmatically cannot produce a row the form would have refused. Set above
  /// the platform's commission: below it, `budget - fee` goes negative, which
  /// migration 0011 clamps to zero and which would mean an inspector working for
  /// nothing.
  static const double minBudget = 50;

  /// The largest budget a buyer may post. A ceiling rather than a plausible
  /// maximum: `numeric(12,2)` holds far more, and the point is to reject a typo
  /// that would otherwise sit on the platform's books until someone noticed.
  static const double maxBudget = 100000;

  /// The budget the create form opens with, pre-filled and editable.
  ///
  /// The standing figure the design showed for a car inspection, which is the one
  /// number a buyer who has no opinion about the price will want anyway. Pre-filled
  /// rather than left blank because an empty box reads as "this service is free"
  /// and because a buyer who must invent a number invents the wrong one.
  static const double defaultBudget = 500;

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
    this.budget = CostEstimate.defaultBudget,
    this.customCentre,
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

  /// The budget the buyer proposes, inclusive of the platform fee.
  ///
  /// The one number on this form that is the buyer's own decision. The database
  /// takes it as given — `enforce_bidding` prices the commission off it — and
  /// freezes it against them the moment an inspector claims the job, so a buyer
  /// cannot raise their own budget after an inspector has looked at it.
  final double budget;

  /// An unlisted centre the buyer would prefer, or null to leave the choice to the
  /// inspector.
  ///
  /// Null is the default and the common case: the design books a centre from the
  /// approved list, and a buyer who has no preference should not have to think
  /// about one. It is never required, and a request with no custom centre is a
  /// completely ordinary request.
  ///
  /// The buyer holds no proof photograph. The proof is the inspector's assertion
  /// that a place is a real inspection shop, so it arrives at booking time and
  /// migration 0010's trigger refuses to let a buyer write it — the field exists on
  /// [CustomCentre] for that reason and is simply left empty here.
  final CustomCentre? customCentre;

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
    // The budget the buyer proposed. The design used to replace this with a fixed
    // structure; migration 0011 gives the column back its original meaning, and the
    // platform's cut of it is computed by `enforce_bidding` rather than by this
    // map — so the client cannot pick its own commission even by accident.
    'price': budget,

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

    // The buyer's preferred centre, when they named one. Written from the same
    // method the inspector's booking uses so the four columns can never be spelled
    // two different ways — and spread into the map rather than nested under a key,
    // because this is the row itself, not a JSON column.
    if (customCentre case final CustomCentre centre) ...centre.toColumns(),
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
    double? budget,
    CustomCentre? customCentre,
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
    budget: budget ?? this.budget,
    customCentre: customCentre ?? this.customCentre,
  );
}
