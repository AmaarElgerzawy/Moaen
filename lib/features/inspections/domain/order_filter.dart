import 'inspection_request.dart';

/// How a list of inspections is filtered.
///
/// Lives here rather than in the admin feature because it describes a query on
/// `car_inspections`, which is this feature's table: an admin-only module that
/// owns the query object would make the inspections data layer import from admin,
/// and the dependency would point the wrong way for everything after it.
///
/// A closed set of named fields rather than a bag of optional parameters, so the
/// repository decides what each control means and no caller can pass a combination
/// that was never designed — six nullable parameters in a row is how an `.eq`
/// silently replaces an `.gte`.
class OrderFilter {
  const OrderFilter({
    this.status,
    this.city,
    this.search = '',
    this.minValue,
    this.from,
    this.to,
  });

  /// No filtering, so a monitor opens on everything rather than on an arbitrary
  /// slice of it.
  static const OrderFilter none = OrderFilter();

  final InspectionStatus? status;

  /// The request's city — the buyer's chosen service city, which is what the job
  /// board is scoped by and therefore what an admin would filter by too.
  final String? city;

  /// A free-text term matched against the reference number, the car, and the
  /// buyer's name.
  ///
  /// Matched in the database with an `ilike`, so it is a real search rather than a
  /// filter applied to a page already in memory. Bounded by the repository's row
  /// cap, which the caller is expected to surface so a truncated result does not
  /// read as a complete one.
  final String search;

  /// The lowest agreed total to include. Null for no floor.
  ///
  /// Filters on `agreed_total` rather than `price`: an agreed total is what a job
  /// is actually worth, and on an open request the agreed total is still null, so a
  /// floor here would exclude every job nobody has finished negotiating.
  final double? minValue;

  /// The inclusive window, on `created_at`. Null at either end for an open-ended
  /// range.
  final DateTime? from;
  final DateTime? to;

  /// True when anything at all is set, which is what shows the monitor's "clear"
  /// control — a control that appears over an unfiltered list has nothing to do.
  bool get isActive =>
      status != null ||
      (city != null && city!.isNotEmpty) ||
      search.trim().isNotEmpty ||
      minValue != null ||
      from != null ||
      to != null;

  /// How many distinct controls are set. For the summary line — "3 filters" — so a
  /// monitor with six inputs does not need six labels to say what it is showing.
  int get activeCount => <bool>[
    status != null,
    (city != null && city!.isNotEmpty),
    search.trim().isNotEmpty,
    minValue != null,
    from != null || to != null,
  ].where((bool set) => set).length;

  /// [to] inclusive to the end of the day the user picked.
  ///
  /// A date picker hands back midnight, so filtering `lte: created_at` on it would
  /// silently exclude everything filed on the day the range appears to end on. The
  /// repository sends the raw [to]; this is what the picker should store instead.
  static DateTime endOfDay(DateTime day) => DateTime(
    day.year,
    day.month,
    day.day,
    23,
    59,
    59,
    999,
  );

  /// [to] as the start of that day, for a range that begins on it.
  static DateTime startOfDay(DateTime day) =>
      DateTime(day.year, day.month, day.day);

  OrderFilter copyWith({
    InspectionStatus? status,
    String? city,
    String? search,
    double? minValue,
    DateTime? from,
    DateTime? to,
    bool clearStatus = false,
    bool clearCity = false,
    bool clearMinValue = false,
    bool clearFrom = false,
    bool clearTo = false,
  }) => OrderFilter(
    status: clearStatus ? null : (status ?? this.status),
    city: clearCity ? null : (city ?? this.city),
    search: search ?? this.search,
    minValue: clearMinValue ? null : (minValue ?? this.minValue),
    from: clearFrom ? null : (from ?? this.from),
    to: clearTo ? null : (to ?? this.to),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderFilter &&
          other.status == status &&
          other.city == city &&
          other.search == search &&
          other.minValue == minValue &&
          other.from == from &&
          other.to == to;

  @override
  int get hashCode => Object.hash(status, city, search, minValue, from, to);

  @override
  String toString() =>
      'OrderFilter(${status?.name ?? '-'}, ${city ?? '-'}, '
      '"$search", ${minValue ?? '-'}, $from, $to)';
}