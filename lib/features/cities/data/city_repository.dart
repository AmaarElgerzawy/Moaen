import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/logging/app_logger.dart';

/// One row of the canonical `cities` table (migration 0005).
///
/// Coordinates are deliberately *not* on this type. They live in [CityCoordinates]
/// behind their own query; see [CityRepository.coordinatesOf] for why that
/// separation is necessary rather than tidiness.
///
/// The board matches `car_inspections.city` against the inspector's
/// `users.location_city` by `lower(btrim(...))` equality. Free text made that
/// comparison a lottery — "Dammam" and "القاهرة" are different strings — so both
/// the buyer's form and the inspector's profile pick from this list instead of
/// typing. The value stored is [nameAr], the Arabic name, which is what the Real
/// World uses in Egypt; [nameEn] exists so the list is still searchable (and
/// sortable) when someone types a Latin city name.
class City {
  const City({required this.nameAr, required this.nameEn});

  factory City.fromRow(Map<String, dynamic> row) => City(
    nameAr: row['name_ar'] as String,
    nameEn: row['name_en'] as String,
  );

  final String nameAr;
  final String nameEn;
}

/// The city list never being readable is not a state the UI can recover from by
/// guessing, so it surfaces as a distinct failure the picker renders with a
/// retry.
class CitiesUnavailable implements Exception {
  const CitiesUnavailable();

  @override
  String toString() => 'CitiesUnavailable';
}

/// Reads the canonical city list.
///
/// Read-only, and the one table `anon` may read: the picker sits on the
/// *sign-up* form, which renders before a session exists. City names are public
/// reference data — the same reasoning that lets a registration form load a
/// country list without signing you in first.
class CityRepository {
  CityRepository(this._client);

  final SupabaseClient _client;

  /// The whole list, in Arabic collation order so a phone presented with the
  /// dropdown sees a stable, predictable ordering in both directions.
  Future<List<City>> listCities() async {
    try {
      final List<dynamic> rows = await _client
          .from('cities')
          .select('name_ar, name_en')
          .order('name_ar');
      return rows
          .map((dynamic row) => City.fromRow(row as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('city list load failed', error, stackTrace);
      throw const CitiesUnavailable();
    }
  }

  /// Where one city is, for the custom-centre map picker to open on.
  ///
  /// A separate query from [listCities] rather than two more columns on it, and
  /// that separation is load-bearing. `listCities` runs on the *sign-up* form,
  /// before a session exists, so adding `latitude, longitude` to its select would
  /// mean the city picker returns PGRST204 — and so cannot render at all — until
  /// migration 0010 has been applied. A missing optional column would break
  /// registration.
  ///
  /// Returns null rather than throwing: a city with no coordinate is a row someone
  /// added by hand, and the correct response is for the map to open on a default
  /// view, not for a centre picker to fail.
  Future<CityCoordinates?> coordinatesOf(String nameAr) async {
    try {
      final List<dynamic> rows = await _client
          .from('cities')
          .select('latitude, longitude')
          .eq('name_ar', nameAr)
          .limit(1);
      if (rows.isEmpty) return null;
      final Map<String, dynamic> row = rows.first as Map<String, dynamic>;
      final num? latitude = row['latitude'] as num?;
      final num? longitude = row['longitude'] as num?;
      if (latitude == null || longitude == null) return null;
      return CityCoordinates(latitude.toDouble(), longitude.toDouble());
    } on PostgrestException catch (error, stackTrace) {
      // Logged and swallowed, unlike [listCities]. The difference is the
      // consequence: here the caller has a working fallback and this only costs it
      // a sensible default view, where there a failure has nowhere to go.
      AppLogger.instance.error(
        'city coordinates lookup failed',
        error,
        stackTrace,
        {'name_ar': nameAr},
      );
      return null;
    }
  }
}

/// A point on the map, in the plainest terms.
///
/// Deliberately not `latlong2`'s `LatLng`: this is a repository result, and
/// importing a mapping library's geometry type into the data layer would put
/// `flutter_map` in the dependency graph of every caller that reads a city's
/// position. The conversion happens once, in the widget that draws the map.
class CityCoordinates {
  const CityCoordinates(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  String toString() => 'CityCoordinates($latitude, $longitude)';
}