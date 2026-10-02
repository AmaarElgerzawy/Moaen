/// An inspection centre that is not in `public.inspection_centres`.
///
/// Two things use this type, and the difference between them matters:
///
///   * A **buyer** names one as a preference while their request is still
///     unclaimed. No fee, no proof — they are expressing a preference, not
///     vouching for a business.
///   * An **inspector** books one when the city has no approved centre, or when
///     the buyer's suggestion turns out to be shut. With a fee the buyer then
///     approves, and with a photograph the inspector stands behind.
///
/// It lives on the request rather than in `inspection_centres` because that table
/// is read-only to clients on purpose: its fee is a price the buyer is shown, so
/// letting anyone insert a row there would let anyone invent a centre at any
/// price. See migration 0010.
///
/// Immutable, like every other domain type here, so a form cannot mutate a value
/// the request is already holding.
class CustomCentre {
  const CustomCentre({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.proofPhotoPath = '',
  });

  /// What the centre is called. Bounds checked here as well as in the database so
  /// the form can refuse before the round trip: 2–120 characters, matching
  /// migration 0010's constraint.
  final String name;

  final double latitude;
  final double longitude;

  /// Storage object path of the inspector's proof photograph, or empty when there
  /// is none yet.
  ///
  /// An object path, not a URL, for the same reason `report_media.media_url` is
  /// one: the `inspection-media` bucket is private, so a signed URL written here
  /// would expire and leave the column pointing at nothing. A reader mints the URL
  /// when it needs to show one.
  final String proofPhotoPath;

  static const int minNameLength = 2;
  static const int maxNameLength = 120;

  /// True once the three columns the database requires together are all usable.
  ///
  /// A partial centre is not storable — migration 0010's shape constraint refuses
  /// a name without a location and a location without a name — so this is the one
  /// predicate that decides whether a form may submit.
  bool get isComplete =>
      name.trim().length >= minNameLength &&
      name.trim().length <= maxNameLength &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  /// True once an inspector has attached a photograph.
  bool get hasProof => proofPhotoPath.isNotEmpty;

  /// The four columns, omitting the proof when there is none.
  ///
  /// One method rather than one per caller because the shape is the same either
  /// way: a buyer simply holds an instance whose [proofPhotoPath] is empty, and
  /// the database's constraint already permits a proof to be absent. Omitting
  /// rather than sending `''` is the same rule the rest of the domain follows —
  /// an empty string is a value, and NULL is "not recorded".
  Map<String, dynamic> toColumns() => <String, dynamic>{
    'custom_centre_name': name.trim(),
    'custom_centre_lat': latitude,
    'custom_centre_lng': longitude,
    if (proofPhotoPath.isNotEmpty) 'custom_centre_proof_photo_url': proofPhotoPath,
  };

  CustomCentre copyWith({
    String? name,
    double? latitude,
    double? longitude,
    String? proofPhotoPath,
  }) => CustomCentre(
    name: name ?? this.name,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    proofPhotoPath: proofPhotoPath ?? this.proofPhotoPath,
  );

  @override
  String toString() => 'CustomCentre($name, $latitude, $longitude)';
}