// Moaen (معاين) — live end-to-end check of the sign-up and sign-in path.
//
// ---------------------------------------------------------------------------
// Why this exists
// ---------------------------------------------------------------------------
// The emulator reported a sign-in failure with nothing in the Android logs, and
// the two obvious suspects — a `handle_new_user` trigger choking on missing
// `user_metadata`, and an RLS policy rejecting the profile insert — were both
// wrong. The cause was a dashboard toggle, invisible from the client.
//
// This suite is the standing check that the path works *end to end through
// GoTrue*, which no other test covers:
//
//   * `test/features/auth/auth_failure_test.dart` proves the client maps a given
//     response correctly. It cannot prove the server ever sends one.
//   * `test/integration/rls_policies_test.dart` proves the policies hold. Its
//     fixtures are written straight into `public.users`, so the trigger never
//     fires and its interaction with GoTrue is untested.
//   * `tool/diagnose_signup_trigger.dart` drives the trigger by inserting
//     directly into `auth.users` — close, but not the real path. A real sign-up
//     differs: GoTrue writes additional columns, and the signup *fails outright*
//     if the trigger raises.
//
// The combination of those three gaps is how a server misconfiguration reached
// a device and looked like a client bug.
//
// ---------------------------------------------------------------------------
// Isolation
// ---------------------------------------------------------------------------
// The account created here is deleted in `tearDown` by cascading through
// `public.users` (the FK is `on delete cascade`). Unlike the RLS suite this
// cannot run in one uncommitted transaction: GoTrue commits its own writes over
// its own connection, so a Dart-side rollback could not undo them. The account
// is therefore created for real and then removed, and the teardown is written to
// say so loudly if it fails.
//
//   MOAEN_DB_URL=<uri> flutter test test/integration/auth_live_test.dart
@Tags(<String>['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moaen/core/env.dart';
import 'package:moaen/features/auth/auth_repository.dart';
import 'package:postgres/postgres.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

/// A fresh address per run, so a stale account can never make a healthy backend
/// look broken.
final String _email =
    'live.${DateTime.now().microsecondsSinceEpoch}@example.com';
const String _password = 'Moaen-Live-Probe-9182!';
const String _fullName = 'Live Signup Probe';
const String _city = 'Riyadh';

String? _dbUrl;
Connection? _conn;
String? _createdUserId;

Future<({int status, Map<String, dynamic> body})> _postAuth(
  String path,
  Map<String, dynamic> payload,
) async {
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);
  try {
    final HttpClientRequest request = await client.postUrl(
      Uri.parse('${Env.supabaseUrl}/auth/v1$path'),
    );
    request.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/json')
      ..set('apikey', Env.supabasePublishableKey)
      ..set('Authorization', 'Bearer ${Env.supabasePublishableKey}');
    request.write(jsonEncode(payload));
    final HttpClientResponse response = await request.close();
    final String text = await response.transform(utf8.decoder).join();
    return (
      status: response.statusCode,
      body: text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>,
    );
  } finally {
    client.close(force: true);
  }
}

/// GoTrue's own error `code`, which is the stable identifier — the `msg` is
/// prose it is free to reword.
String? _errorCode(Map<String, dynamic> body) => body['error_code'] as String?;

/// A single actionable sentence for a misconfigured project, so a failure here
/// names the fix instead of restating the symptom.
String _providerDisabledHint() =>
    'The Supabase project has the Email sign-in provider switched off. '
    'Enable it in the dashboard under Authentication -> Sign In / Providers -> '
    'Email -> "Enable Email provider", then re-run. Nothing in the app can '
    'work around this: GoTrue rejects both sign-up and the password grant '
    'before the request reaches the database.';

void main() {
  final String? databaseUrl = Platform.environment['MOAEN_DB_URL'];

  // The same rule as the RLS suite, and it matters more here. These tests reach
  // the network as well as the database, so without this gate a bare
  // `flutter test` on a machine that has never been pointed at the project would
  // make live sign-up attempts — and, on a healthy project, would create real
  // accounts. A missing credential is a skip; a credential that is present but
  // wrong deliberately still fails.
  final String? skipReason = (databaseUrl == null || databaseUrl.isEmpty)
      ? 'MOAEN_DB_URL is not set. Point it at the project to verify sign-up '
            'and sign-in against live Supabase auth.'
      : null;

  // Stated once rather than at each call site, where a single omission would
  // turn "no credentials" into a live network call.
  void liveTest(String description, Future<void> Function() body) {
    test(description, body, skip: skipReason);
  }

  setUpAll(() async {
    _dbUrl = databaseUrl;
    if (_dbUrl == null) return;
    _conn = await Connection.openFromUrl(_dbUrl!);
  });

  tearDownAll(() async {
    final Connection? conn = _conn;
    final String? id = _createdUserId;
    if (conn != null && id != null) {
      // The FK on public.users is `on delete cascade`, so one delete is enough.
      // If this throws, the account survives: the file header says so, and the
      // test that created it is one that failed loudly already.
      await conn.execute(
        'delete from auth.users where id = \$1',
        parameters: <Object?>[id],
      );
    }
    await conn?.close();
  });

  liveTest('a real sign-up creates the account, the profile, and a session', () async {
    final ({int status, Map<String, dynamic> body}) response = await _postAuth(
      '/signup',
      <String, dynamic>{
        'email': _email,
        'password': _password,
        'data': <String, dynamic>{
          'full_name': _fullName,
          'role': 'inspector',
          'city': _city,
        },
      },
    );

    final String? code = _errorCode(response.body);
    expect(
      code,
      isNot('email_provider_disabled'),
      reason: _providerDisabledHint(),
    );
    expect(
      response.status,
      lessThan(300),
      reason: 'signup failed: ${response.body}',
    );

    final Map<String, dynamic>? user =
        response.body['user'] as Map<String, dynamic>?;
    expect(user, isNotNull, reason: 'no account came back: ${response.body}');
    _createdUserId = user!['id'] as String?;

    // `mailer_autoconfirm: true` is set on the project, so sign-up must return a
    // session rather than requiring a confirmation email. If this fails, the
    // app shows "check your email to confirm" and nobody can reach the
    // dashboard.
    expect(
      response.body['access_token'],
      isNotNull,
      reason: 'sign-up returned no session, so the app cannot sign the user in',
    );

    // The trigger. Written by GoTrue's real insert, not by a fixture, and read
    // over a direct connection because the point is to see the row GoTrue's
    // transaction committed.
    final Result profile = await _conn!.execute(
      'select full_name, email, role::text as role, location_city '
      'from public.users where id = \$1',
      parameters: <Object?>[_createdUserId],
    );
    expect(
      profile,
      isNotEmpty,
      reason: 'handle_new_user did not create a public.users row',
    );
    expect(profile.first[0], _fullName, reason: 'full_name from metadata');
    expect(profile.first[1], _email);
    expect(profile.first[2], 'inspector', reason: 'role from metadata');
    expect(profile.first[3], _city, reason: 'location_city from the city key');
  });

  liveTest('the same account can then sign in with its password', () async {
    final ({int status, Map<String, dynamic> body}) response = await _postAuth(
      '/token?grant_type=password',
      <String, dynamic>{'email': _email, 'password': _password},
    );

    expect(
      _errorCode(response.body),
      isNot('email_provider_disabled'),
      reason: _providerDisabledHint(),
    );
    expect(
      response.status,
      lessThan(300),
      reason: 'password grant failed: ${response.body}',
    );
    expect(response.body['access_token'], isNotNull);
  });

  // Asserted against the live project because the only thing that has ever made
  // this fail is a server-side setting, and a client-only test would keep
  // passing while the app is completely unusable.
  liveTest('the Email sign-in provider is enabled on the project', () async {
    final ({int status, Map<String, dynamic> body}) response = await _postAuth(
      '/signup',
      <String, dynamic>{
        'email': _email,
        'password': _password,
        'data': <String, dynamic>{'full_name': _fullName},
      },
    );

    expect(
      _errorCode(response.body),
      isNot('email_provider_disabled'),
      reason: _providerDisabledHint(),
    );
  });

  group('the client maps what this project actually returns', () {
    // Guards the mapping against the live responses, not a transcription of the
    // documentation. The two observed shapes of a disabled provider differ in
    // status and prose, and a mapping written from docs alone missed it.
    //
    // Not gated: it needs no network and no database, and a mapping that only
    // ran when credentials were present would be exactly the mapping that went
    // unverified.
    test('both shapes of a disabled provider map to one reason', () {
      for (final (String?, String) shape in <(String?, String)>[
        ('email_provider_disabled', 'Email signups are disabled'),
        ('email_provider_disabled', 'Email logins are disabled'),
      ]) {
        expect(
          AuthRepository.reasonFor(
            AuthException(shape.$2, code: shape.$1),
          ),
          AuthFailureReason.providerDisabled,
        );
      }
    });
  });
}
