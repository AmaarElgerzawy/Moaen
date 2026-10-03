/// How the platform's commission is expressed.
///
/// Mirrors the `commission_type` enum from migration 0011. [fromName] falls back
/// to [fixed] for an unknown value, which is the row's own default — so a column
/// that has grown a third state cannot leave the admin panel unable to save.
enum CommissionType {
  fixed,
  percent;

  static CommissionType fromName(String? value) =>
      CommissionType.values.firstWhere(
        (CommissionType type) => type.name == value,
        orElse: () => CommissionType.fixed,
      );

  /// The row to write when an admin picks this type.
  String get columnName => name;
}

/// The platform's commission, as configured.
///
/// A value object rather than two loose doubles because the type and the number
/// cannot be separated: a `49` under [CommissionType.percent] is not a 49%
/// commission, it is a number that means nothing, and the form that collects
/// them should not be able to produce it either.
class Commission {
  const Commission({
    this.type = CommissionType.fixed,
    this.value = defaultFixedValue,
  });

  factory Commission.fromRow(Map<String, dynamic> row) => Commission(
    type: CommissionType.fromName(row['commission_type'] as String?),
    value: (row['commission_value'] as num?)?.toDouble() ?? defaultFixedValue,
  );

  /// The commission migration 0011 provisions, and the value the design was built
  /// around. Not a price list — a default that is replaced by the first admin save.
  static const double defaultFixedValue = 49;

  final CommissionType type;

  /// SAR under [CommissionType.fixed], percent under [CommissionType.percent].
  final double value;

  /// What the platform takes on a budget of [total].
  ///
  /// The same arithmetic as the database's `platform_fee_for`, written out here
  /// for the screens that show the split *before* a request exists — the create
  /// form and the inspector's earnings line.
  ///
  /// Two guards, and both matter. Clamped to [total], because a budget below the
  /// commission must not produce a negative fee that would then hand the inspector
  /// more than the buyer is paying. And zero for a non-positive total, because
  /// `least` of a negative fee and a negative budget is the wrong answer twice
  /// over.
  ///
  /// The create form reads the live value from `platform_settings` rather than
  /// this class — [value] here is only the cached copy the form falls back to if
  /// that read fails. If the two ever disagreed, the database's number is the one
  /// that ends up on the row, and the form would be off by the difference for the
  /// half-second between the two reads.
  double feeFor(double total) {
    if (total <= 0) return 0;
    final double raw = type == CommissionType.percent
        ? (total * value / 100).roundToDouble()
        : value;
    return raw > total ? total : raw;
  }

  /// What an inspector keeps from a budget of [total].
  double netFor(double total) => total - feeFor(total);

  /// The columns an admin's save writes.
  ///
  /// Only the two fields. `updated_at` and `updated_by` are assigned by the
  /// trigger rather than by the client, so an audit row cannot be backdated.
  Map<String, dynamic> toRow() => <String, dynamic>{
    'commission_type': type.name,
    'commission_value': value,
  };

  Commission copyWith({CommissionType? type, double? value}) => Commission(
    type: type ?? this.type,
    value: value ?? this.value,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Commission && other.type == type && other.value == value;

  @override
  int get hashCode => Object.hash(type, value);

  @override
  String toString() => 'Commission(${type.name}, $value)';
}