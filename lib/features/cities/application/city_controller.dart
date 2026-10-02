import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../data/city_repository.dart';

final cityRepositoryProvider = Provider<CityRepository>(
  (Ref ref) => CityRepository(ref.watch(supabaseClientProvider)),
);

/// The canonical city list, loaded once and shared by every picker: the
/// sign-up form, the create-request form and the profile editor all read the
/// same list, which is what guarantees that a city typed nowhere produces a
/// request that matches an inspector's profile.
final citiesProvider = FutureProvider<List<City>>(
  (Ref ref) => ref.watch(cityRepositoryProvider).listCities(),
);

/// Where one city is, for the custom-centre map picker to open on.
///
/// Null is the normal answer for a city with no coordinate and also for a failed
/// lookup, because both mean the same thing to the only caller: open the map on
/// the default view instead. Keyed by `name_ar` rather than looked up inside the
/// city list, so this costs one small query only when a picker actually opens and
/// does not lengthen the sign-up form's read.
final cityCoordinatesProvider =
    FutureProvider.family<CityCoordinates?, String>(
      (Ref ref, String nameAr) =>
          ref.watch(cityRepositoryProvider).coordinatesOf(nameAr),
    );