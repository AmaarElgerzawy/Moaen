// Is the *password* grant also gated on the disabled email provider, or only
// sign-up? GoTrue answers this differently across versions, so it is asked
// rather than assumed.
//
// Creates a throwaway confirmed account with a pgcrypto bcrypt hash (the same
// format GoTrue stores), attempts a password grant, then removes the account.
// The delete cascades to public.users via the FK, so nothing is left behind.
//
//   MOAEN_DB_URL=<uri> dart run tool/diagnose_password_grant.dart
import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';

const String _url = 'https://ybglobvcqgkfclvkjkri.supabase.co';
const String _key = 'sb_publishable_qGZ3U2FHarEMD9Mtsg8mHg_eYsNswOp';
const String _email = 'password.grant.probe@example.com';
const String _password = 'Moaen-Probe-9182!';
const String _id = '00000000-0000-4000-8000-000000000002';

Future<void> main() async {
  final String? dbUrl = Platform.environment['MOAEN_DB_URL'];
  if (dbUrl == null || dbUrl.isEmpty) {
    stderr.writeln('MOAEN_DB_URL is not set.');
    exit(78);
  }

  final Connection conn = await Connection.openFromUrl(dbUrl);
  final HttpClient client = HttpClient();

  try {
    await conn.execute(
      "delete from auth.users where id = \$1",
      parameters: [_id],
    );
    await conn.execute(
      r'''
      insert into auth.users
        (id, email, encrypted_password, email_confirmed_at,
         raw_user_meta_data, aud, role, created_at, updated_at)
      values
        ($1, $2, crypt($3, gen_salt('bf')), now(),
         '{"full_name":"Password Grant Probe","role":"client"}'::jsonb,
         'authenticated', 'authenticated', now(), now())
      ''',
      parameters: [_id, _email, _password],
    );
    stdout.writeln('probe account created and email-confirmed');

    final HttpClientRequest request = await client.postUrl(
      Uri.parse('$_url/auth/v1/token?grant_type=password'),
    );
    request.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/json')
      ..set('apikey', _key)
      ..set('Authorization', 'Bearer $_key');
    request.write(jsonEncode(<String, dynamic>{
      'email': _email,
      'password': _password,
    }));

    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    stdout.writeln('--- password grant -> HTTP ${response.statusCode}');
    stdout.writeln(
      body.replaceAll(
        RegExp(r'"(access_token|refresh_token)"\s*:\s*"[^"]*"'),
        r'"\1":"<redacted>"',
      ),
    );
  } finally {
    try {
      await conn.execute(
        "delete from auth.users where id = \$1",
        parameters: [_id],
      );
      stdout.writeln('probe account removed');
    } on ServerException catch (error) {
      stdout.writeln('COULD NOT REMOVE PROBE ACCOUNT $_id: ${error.message}');
    }
    client.close(force: true);
    await conn.close();
  }
}
