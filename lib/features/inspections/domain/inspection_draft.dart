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
/// The figures below are placeholders. They are stated in one place so that
/// replacing them with a real source is a one-line change, and so that no screen
/// hard-codes a number that will need hunting down later.
class CostEstimate {
  const CostEstimate({required this.inspectionFee, this.travelFee = 0});

  /// The inspection itself.
  final double inspectionFee;

  /// Getting to the car and back. Zero in most cities; non-zero where the car
  /// is outside the city the inspection is booked in.
  final double travelFee;

  double get total => inspectionFee + travelFee;

  /// Placeholder base fee, in EGP.
  ///
  /// NOT a price list. Replace with a real source before launch; see the class
  /// doc for why this is a display value rather than a stored one.
  static const double baseInspectionFee = 500;

  /// The estimate for a request in [city].
  ///
  /// No city is treated as remote for now. That is a product decision this
  /// codebase should not make silently: if travel is ever priced by distance,
  /// this is the single place that has to change.
  static CostEstimate forCity(String city) =>
      const CostEstimate(inspectionFee: baseInspectionFee);

  /// Formats an amount for display, e.g. `500 EGP`.
  ///
  /// A trailing `.00` is dropped so the common whole-amount case does not read
  /// as a precise figure it is not, but a genuine 495.50 is kept.
  static String format(double amount) {
    final bool whole = amount == amount.roundToDouble();
    final String digits = whole
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
    return '$digits EGP';
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
