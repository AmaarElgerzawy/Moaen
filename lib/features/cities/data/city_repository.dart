import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/logging/app_logger.dart';

/// One row of the canonical `cities` table (migration 0005).
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
}