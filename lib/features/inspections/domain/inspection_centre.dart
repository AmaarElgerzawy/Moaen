/// An approved inspection centre — one row of `public.inspection_centres`.
///
/// A table rather than a list of literals because the centre's *fee* is a line on
/// the buyer's invoice. A dropdown of hard-coded names cannot produce the 300 the
/// invoice shows; the figure has to come from the same row the name does, or the
/// two can disagree and the buyer approves one number and is charged another.
class InspectionCentre {
  const InspectionCentre({
    required this.id,
    required this.name,
    required this.city,
    required this.fee,
    this.isBlocked = false,
  });

  final String id;
  final String name;
  final String city;

  /// The centre's own inspection fee, in SAR.
  final double fee;

  /// Whether an admin has suspended this centre.
  ///
  /// Migration 0011. Read here rather than only in the policy because the admin
  /// panel is the one screen that must *show* suspended centres — the booking
  /// dropdown's policy hides them, and the reason an admin can un-suspend one is
  /// that this flag comes back on a read.
  ///
  /// Defaults to false so a row read without the column — the app running against
  /// a database where 0011 has not been applied — shows a working centre rather
  /// than throwing.
  final bool isBlocked;

  factory InspectionCentre.fromRow(Map<String, dynamic> row) => InspectionCentre(
    id: row['id'] as String,
    name: row['name'] as String,
    city: row['city'] as String,
    // `numeric` over PostgREST may arrive as an int, a double or a string; see
    // the note on `InspectionRequest.price`.
    fee: switch (row['fee']) {
      final num value => value.toDouble(),
      final String value => double.tryParse(value) ?? 0,
      _ => 0,
    },
    isBlocked: row['is_blocked'] == true,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InspectionCentre &&
          other.id == id &&
          other.name == name &&
          other.city == city &&
          other.fee == fee &&
          other.isBlocked == isBlocked;

  @override
  int get hashCode => Object.hash(id, name, city, fee, isBlocked);

  @override
  String toString() => 'InspectionCentre($name, $city)';

  /// The same centre with some fields replaced.
  ///
  /// Present for the one mutation anyone performs: the admin panel suspending and
  /// restoring a centre. Written out rather than mutating in place because the
  /// domain type is immutable everywhere else, and an admin's list is the same list
  /// a booking dropdown is reading.
  InspectionCentre copyWith({
    String? name,
    String? city,
    double? fee,
    bool? isBlocked,
  }) => InspectionCentre(
    id: id,
    name: name ?? this.name,
    city: city ?? this.city,
    fee: fee ?? this.fee,
    isBlocked: isBlocked ?? this.isBlocked,
  );
}
