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
  });

  final String id;
  final String name;
  final String city;

  /// The centre's own inspection fee, in SAR.
  final double fee;

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
  );

  @override
  String toString() => 'InspectionCentre($name, $city)';
}
