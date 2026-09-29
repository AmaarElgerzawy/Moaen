import 'package:moaen/features/cities/data/city_repository.dart';

/// The cities the pickers offer in widget tests.
///
/// `nameAr` holds an English city name on purpose: the tests assert on the
/// *value* a form submits (for example `sent.city == 'Giza'`), and asserting on
/// an Arabic literal would test the translation rather than the behaviour. The
/// real seed data in migration 0005 replaces this list in production.
const List<City> testCities = <City>[
  City(nameAr: 'Cairo', nameEn: 'Cairo'),
  City(nameAr: 'Giza', nameEn: 'Giza'),
  City(nameAr: 'Alexandria', nameEn: 'Alexandria'),
  City(nameAr: 'Mansoura', nameEn: 'Mansoura'),
];