import '../../inspections/domain/inspection_request.dart';

/// Orders in one status, as the monitor's summary row.
///
/// Reads the `admin_order_summary` view from migration 0011. Grouped in the
/// database rather than in Dart so the counts cannot drift from the rows they
/// describe, and so the panel can render the whole status breakdown from one small
/// read instead of fetching every order and counting on the phone.
class OrderSummary {
  const OrderSummary({
    required this.status,
    this.orders = 0,
    this.value = 0,
    this.platformFees = 0,
  });

  factory OrderSummary.fromRow(Map<String, dynamic> row) => OrderSummary(
    // The view casts the enum to text, so this never throws on a status this build
    // has not heard of — [InspectionStatus.fromName] falls back to `pending`, which
    // for an unknown status would mislabel the row. The raw name is kept instead
    // for exactly that case, and the screen shows it verbatim.
    status: row['status'] as String? ?? 'pending',
    orders: _asInt(row['orders']),
    value: _asDouble(row['value']),
    platformFees: _asDouble(row['platform_fees']),
  );

  /// The raw status name, as the database wrote it.
  ///
  /// A string rather than the enum, because this row is a *count grouped by* a
  /// status, including any status a future migration adds. Mapping it to
  /// [InspectionStatus] would silently fold that new state into `pending`, and the
  /// monitor would then under-report the one status nobody has written copy for.
  final String status;

  final int orders;
  final double value;
  final double platformFees;

  /// The status as the app knows it, or null when it does not.
  InspectionStatus? get knownStatus => InspectionStatus.values
      .where((InspectionStatus s) => s.name == status)
      .firstOrNull;

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  static int _asInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}

/// One row in the orders monitor.
///
/// The monitor lists inspections for an admin, which is the only role with a
/// policy that admits them all. Everything an admin sees here is the same
/// [InspectionRequest] the buyer and the inspector see — there is no admin-only
/// projection, deliberately, so a figure on this screen and the same figure on a
/// participant's screen come from one type and cannot disagree.
///
/// The filter the monitor applies is `OrderFilter`, from the inspections feature,
/// for the same layering reason: it describes a query on `car_inspections`.
typedef AdminOrder = InspectionRequest;