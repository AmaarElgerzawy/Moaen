// One-off diagnostic: has any account ever been created, and does the
// `handle_new_user` trigger actually work?
//
// Existence check: the trigger body has never been observed to run if
// `auth.users` is empty, which would mean the failure is upstream of it.
//
// Trigger check: insert a throwaway `auth.users` row in a transaction and roll
// back. The insert drives the real `after insert on auth.users` trigger, so a
// successful round trip proves the trigger populates `public.users` correctly
// without leaving an account behind.
//
//   MOAEN_DB_URL=<uri> dart run tool/diagnose_signup_trigger.dart
import 'dart:io';

import 'package:postgres/postgres.dart';

Future<void> main() async {
  final String? url = Platform.environment['MOAEN_DB_URL'];
  if (url == null || url.isEmpty) {
    stderr.writeln('MOAEN_DB_URL is not set.');
    exit(78);
  }

  final Connection conn = await Connection.openFromUrl(url);
  try {
    final Result accounts = await conn.execute(
      "select count(*) as n from auth.users",
    );
    final Result profiles = await conn.execute(
      "select count(*) as n from public.users",
    );
    stdout.writeln('auth.users rows      : ${accounts.isEmpty ? 0 : accounts.first[0]}');
    stdout.writeln('public.users rows    : ${profiles.isEmpty ? 0 : profiles.first[0]}');

    // Drives the trigger, then rolls back. The id is fabricated because
    // `public.users.id` references it, so it has to satisfy the FK.
    await conn.execute('begin');
    try {
      final String id = '00000000-0000-4000-8000-000000000001';
      await conn.execute(
        "delete from auth.users where id = \$1",
        parameters: [id],
      );
      await conn.execute(
        '''
        insert into auth.users
          (id, email, raw_user_meta_data, created_at, updated_at)
        values
          (\$1, 'trigger.probe@example.com',
           '{"full_name":"Trigger Probe","role":"inspector","city":"Riyadh"}'::jsonb,
           now(), now())
        ''',
        parameters: [id],
      );
      final Result created = await conn.execute(
        "select full_name, email, role::text as role, location_city, phone "
        "from public.users where id = \$1",
        parameters: [id],
      );
      if (created.isEmpty) {
        stdout.writeln('TRIGGER FAILED: no public.users row was created.');
      } else {
        stdout.writeln('trigger ok, public.users row:');
        created.first.toColumnMap().forEach((k, v) => stdout.writeln('  $k = $v'));
      }
    } on ServerException catch (error) {
      stdout.writeln('TRIGGER FAILED: ${error.message}');
      stdout.writeln('  sqlstate ${error.code}  detail ${error.detail}');
    } finally {
      await conn.execute('rollback');
    }
    stdout.writeln('(rolled back; no account was created)');
  } finally {
    await conn.close();
  }
}
