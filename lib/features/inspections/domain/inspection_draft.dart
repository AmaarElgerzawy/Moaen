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
    this.sellerPhone = '',
    this.sellerLocationAddress = '',
    this.city = '',
    this.clientNotes = '',
    this.budget = '',
  });

  final String carMake;
  final String carModel;
  final String carYear;
  final String sellerPhone;
  final String sellerLocationAddress;
  final String city;
  final String clientNotes;

  /// Kept as text, not a number.
  ///
  /// A `TextEditingController` holding a double cannot represent the
  /// intermediate states of typing: an empty field, a lone `-`, or `500.` while
  /// the trailing digit is still being entered. Parsing happens on submit, into
  /// the nullable [budgetAmount].
  final String budget;

  /// The budget as a number, or null when it is absent or unparseable.
  double? get budgetAmount {
    final String input = budget.trim();
    // A trailing bare decimal point is rejected even though `double.tryParse`
    // accepts it and returns 5.0 for "5.". Someone typing `500.` is mid-way
    // through `500.50`, and accepting the partial value silently turns their
    // budget into a different number from the one they meant. The cost of
    // refusing is one more keystroke; the cost of accepting is a quote the
    // buyer did not agree to.
    if (input.endsWith('.')) return null;

    final double? parsed = double.tryParse(input);
    if (parsed == null || !parsed.isFinite || parsed < 0) return null;
    return parsed;
  }

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
  /// Requires a non-null [year] and [budgetAmount]; the caller validates first,
  /// which is why both are non-null assertions here rather than silently
  /// defaulting to something the database would reject.
  Map<String, dynamic> toRow(String clientId) => <String, dynamic>{
    'client_id': clientId,
    'car_make': carMake.trim(),
    'car_model': carModel.trim(),
    'car_year': year!,
    'seller_phone': sellerPhone.trim(),
    'seller_location_address': sellerLocationAddress.trim(),
    'city': city.trim(),
    'price': budgetAmount!,
    // Empty means NULL rather than an empty string: `check (char_length(...) <=
    // 1000)` passes either way, but '' would show up in a report as a note the
    // buyer wrote, which is not the same as no note.
    if (clientNotes.trim().isNotEmpty) 'client_notes': clientNotes.trim(),
  };

  InspectionDraft copyWith({
    String? carMake,
    String? carModel,
    String? carYear,
    String? sellerPhone,
    String? sellerLocationAddress,
    String? city,
    String? clientNotes,
    String? budget,
  }) => InspectionDraft(
    carMake: carMake ?? this.carMake,
    carModel: carModel ?? this.carModel,
    carYear: carYear ?? this.carYear,
    sellerPhone: sellerPhone ?? this.sellerPhone,
    sellerLocationAddress: sellerLocationAddress ?? this.sellerLocationAddress,
    city: city ?? this.city,
    clientNotes: clientNotes ?? this.clientNotes,
    budget: budget ?? this.budget,
  );
}
