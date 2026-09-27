// One-off cleanup: removes the accounts left behind by `auth_probe.dart` runs
// that predate its own cleanup, plus any other throwaway address.
//
// Deliberately narrow. It matches only `example.com` addresses whose local part
// starts with a known probe prefix, so it cannot touch a real account even if a
// real account is ever registered on an example.com address.
//
//   MOAEN_DB_URL=<uri> dart run tool/cleanup_probe_accounts.dart
import 'dart:io';

import 'package:postgres/postgres.dart';

const List<String> _prefixes = <String>[
  'probe.',
  'live.',
  'password.grant.probe',
  'trigger.probe',
];

Future<void> main() async {
  final String? url = Platform.environment['MOAEN_DB_URL'];
  if (url == null || url.isEmpty) {
    stderr.writeln('MOAEN_DB_URL is not set.');
    exit(78);
  }

  final Connection conn = await Connection.openFromUrl(url);
  try {
    final Result before = await conn.execute(
      "select id::text as id, email from auth.users order by email",
    );
    stdout.writeln('accounts before: ${before.length}');
    for (final row in before) {
      stdout.writeln('  ${row[0]}  ${row[1]}');
    }

    // The prefix match is on the local part only, and case-insensitively, so a
    // renamed probe is still caught. `email` on auth.users is always lowercased
    // by GoTrue.
    final Result removed = await conn.execute(
      "delete from auth.users where email ilike any (\$1) returning email",
      parameters: <Object?>[
        _prefixes.map((String p) => '$p%@example.com').toList(),
      ],
    );
    stdout.writeln('removed: ${removed.length}');
    for (final row in removed) {
      stdout.writeln('  ${row[0]}');
    }

    final Result after = await conn.execute(
      'select count(*) as n from auth.users',
    );
    final Result profiles = await conn.execute(
      'select count(*) as n from public.users',
    );
    stdout.writeln('accounts after: ${after.first[0]}');
    stdout.writeln('profiles after: ${profiles.first[0]}');
  } finally {
    await conn.close();
  }
}
