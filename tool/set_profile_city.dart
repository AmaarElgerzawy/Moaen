// Fixes an inspector's registered service city in the live database.
//
// Before P10 both sides typed cities as free text, so an inspector who signed
// up with a hand-typed city can be stuck with a spelling no buyer ever matches
// ("دولي" instead of the canonical "القاهرة"). This tool corrects the stored
// value so the RLS board match (`lower(btrim(city)) =
// lower(btrim(location_city))`) starts admitting requests again.
//
//   MOAEN_DB_URL=<uri> dart run tool/set_profile_city.dart <email> <city>
//
// The city is stored verbatim; pass the canonical `name_ar` from the cities
// table (the app now writes these values everywhere).
import 'dart:io';

import 'package:postgres/postgres.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'usage: MOAEN_DB_URL=<uri> dart run tool/set_profile_city.dart '
      '<email> <city>',
    );
    exit(64);
  }
  final String email = args[0];
  final String city = args[1];

  final String? url = Platform.environment['MOAEN_DB_URL'];
  if (url == null || url.isEmpty) {
    stderr.writeln('MOAEN_DB_URL is not set.');
    exit(78); // EX_CONFIG
  }

  final Connection conn = await Connection.openFromUrl(url);
  try {
    final Result before = await conn.execute(
      'select email, location_city, (role)::text '
      'from public.users where email = \$1',
      parameters: <Object?>[email],
    );
    if (before.isEmpty) {
      stderr.writeln('no user with email $email');
      exit(66); // EX_NOINPUT
    }
    final Object? oldCity = before.first[1];
    stdout.writeln('current: email=${before.first[0]} city=[$oldCity]');

    await conn.execute(
      'update public.users set location_city = \$2 where email = \$1',
      parameters: <Object?>[email, city],
    );

    final Result after = await conn.execute(
      'select location_city from public.users where email = \$1',
      parameters: <Object?>[email],
    );
    stdout.writeln('updated: city=[${after.first[0]}]');
  } finally {
    await conn.close();
  }
}