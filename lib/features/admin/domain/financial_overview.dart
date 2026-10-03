/// What the platform has actually taken, as one row.
///
/// Reads the `admin_financial_overview` view from migration 0011 rather than
/// summing in Dart. The arithmetic lives next to the data it describes, so the
/// three places that show money — this panel, the invoice and the report — cannot
/// come to different conclusions about the same payments.
///
/// The distinction the type exists to hold: [platformRevenue] is fees on payments
/// that were *released*. [heldInEscrow] is money the platform is holding and has
/// not earned, and [refunded] is money it gave back. They are separate fields
/// rather than one "volume" number because a total of the three would describe
/// nothing.
class FinancialOverview {
  const FinancialOverview({
    this.collectedVolume = 0,
    this.platformRevenue = 0,
    this.heldInEscrow = 0,
    this.refunded = 0,
    this.completedPayments = 0,
    this.totalPayments = 0,
  });

  factory FinancialOverview.fromRow(Map<String, dynamic> row) => FinancialOverview(
    // The view casts every figure to `numeric(12,2)`, which PostgREST may hand
    // back as a JSON number or as a string. Both are handled: a money column that
    // throws on a round number is a bug that only appears in production.
    collectedVolume: _asDouble(row['collected_volume']),
    platformRevenue: _asDouble(row['platform_revenue']),
    heldInEscrow: _asDouble(row['held_in_escrow']),
    refunded: _asDouble(row['refunded']),
    completedPayments: _asInt(row['completed_payments']),
    totalPayments: _asInt(row['total_payments']),
  );

  /// The gross value of released payments.
  final double collectedVolume;

  /// The platform's commission on those payments.
  final double platformRevenue;

  /// Sitting in escrow, not yet earned.
  final double heldInEscrow;

  /// Given back.
  final double refunded;

  final int completedPayments;
  final int totalPayments;

  /// True before any payment has been settled.
  bool get isEmpty => totalPayments == 0;

  /// The commission as a share of what was collected.
  ///
  /// Null when nothing has been collected, rather than zero: "the platform has
  /// taken nothing so it earns no share" and "no ratio can be stated" are different
  /// sentences, and a donut chart drawn from the second one is a lie.
  double? get takeRate => collectedVolume <= 0 ? null : platformRevenue / collectedVolume;

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  static int _asInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}