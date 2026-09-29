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