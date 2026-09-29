import 'package:moaen/features/cities/data/city_repository.dart';

/// The cities the pickers offer in widget tests.
///
/// `nameAr` holds an English city name on purpose: the tests assert on the
/// *value* a form submits (for example `sent.city == 'Jeddah'`), and asserting on
/// an Arabic literal would test the translation rather than the behaviour. The
/// real seed data in migration 0006 replaces this list in production.
const List<City> testCities = <City>[
  City(nameAr: 'Dammam', nameEn: 'Dammam'),
  City(nameAr: 'Jeddah', nameEn: 'Jeddah'),
  City(nameAr: 'Riyadh', nameEn: 'Riyadh'),
  City(nameAr: 'Makkah', nameEn: 'Makkah'),
];