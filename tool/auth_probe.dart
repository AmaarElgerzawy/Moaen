// Probes the live GoTrue + PostgREST path the sign-up / sign-in flow depends on.
//
// Deliberately uses `dart:io` rather than an HTTP package: the endpoints under
// test are the same ones `supabase_flutter` calls, so a failure here is a
// server-side or trigger-side fault, and reproducing the call by hand is what
// tells the two apart. `flutter run` shows the app's symptom; this shows the
// server's answer before the SDK has a chance to translate it.
//
// Usage:
//   MOAEN_DB_URL=<uri> dart run tool/auth_probe.dart
//   dart run tool/auth_probe.dart --url https://xxx.supabase.co
//
// With MOAEN_DB_URL it deletes the probe account on the way out. Without it the
// account survives and the id is printed with the statement to remove it.
//
// Only the *publishable* key is used. It is public by design and RLS, not this
// key, is what protects the data.

import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';

const String _defaultUrl = 'https://ybglobvcqgkfclvkjkri.supabase.co';
const String _defaultKey = 'sb_publishable_qGZ3U2FHarEMD9Mtsg8mHg_eYsNswOp';

/// Replaces every access/refresh token so a transcript can be pasted in an
/// issue without handing over a live session.
///
/// [replaceAllMapped] rather than [replaceAll], and the reason is worth stating
/// because it cost two attempts: `replaceAll` does **not** expand a group
/// reference in the replacement, so `r'"$1":"<redacted>"'` — and its `\1`
/// variant before it — are both emitted verbatim, producing `"$1":"<redacted>"`
/// and `"\1":"<redacted>"`. The token *is* hidden either way, which is the
/// dangerous part: the output looks redacted and correct while no longer naming
/// the field it redacted, and a reader has no way to tell that from a genuine
/// response. Only the mapped form substitutes the group.
String _redact(String body) => body.replaceAllMapped(
  RegExp(r'"(access_token|refresh_token)"\s*:\s*"[^"]*"'),
  (Match match) => '"${match.group(1)}":"<redacted>"',
);

Future<({int status, String body})> _post(
  HttpClient client,
  String url,
  Map<String, String> headers,
  Object payload,
) async {
  final HttpClientRequest request = await client.postUrl(Uri.parse(url));
  request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  headers.forEach(request.headers.set);
  request.write(jsonEncode(payload));

  final HttpClientResponse response = await request.close();
  return (status: response.statusCode, body: await response.transform(utf8.decoder).join());
}

Future<({int status, String body})> _get(
  HttpClient client,
  String url,
  Map<String, String> headers,
) async {
  final HttpClientRequest request = await client.getUrl(Uri.parse(url));
  headers.forEach(request.headers.set);
  final HttpClientResponse response = await request.close();
  return (status: response.statusCode, body: await response.transform(utf8.decoder).join());
}

Future<void> main(List<String> args) async {
  final int urlFlag = args.indexOf('--url');
  final String base = (urlFlag >= 0 && urlFlag + 1 < args.length)
      ? args[urlFlag + 1]
      : _defaultUrl;
  const String key = _defaultKey;
  final String auth = '$base/auth/v1';

  // A fresh address every run: a cached "already registered" would make a
  // healthy backend look broken and vice versa.
  final String email =
      'probe.${DateTime.now().microsecondsSinceEpoch}@example.com';
  const String password = 'Moaen-Probe-9182!';

  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);
  final Map<String, String> headers = <String, String>{
    'apikey': key,
    'Authorization': 'Bearer $key',
  };

  void report(String step, int status, String body) {
    stdout.writeln('--- $step -> HTTP $status');
    stdout.writeln(_redact(body.trim().isEmpty ? '(empty body)' : body));
  }

  try {
    // 1. Sign-up. The `handle_new_user` trigger fires inside this request, so a
    //    failure here is a trigger failure, and GoTrue reports it as a generic
    //    "Database error saving new user" rather than as a constraint name.
    final ({int status, String body}) signup = await _post(
      client,
      '$auth/signup',
      headers,
      <String, dynamic>{
        'email': email,
        'password': password,
        'data': <String, dynamic>{
          'full_name': 'Probe Account',
          'role': 'client',
        },
      },
    );
    report('signup', signup.status, signup.body);

    if (signup.status >= 300) {
      stdout.writeln('\nSign-up itself failed. Nothing downstream can be concluded: the '
          'fault is in GoTrue or in the auth.users trigger.');
      exitCode = 1;
      return;
    }

    final Map<String, dynamic> created = jsonDecode(signup.body) as Map<String, dynamic>;
    final Map<String, dynamic>? user = created['user'] as Map<String, dynamic>?;
    final String? accessToken = created['access_token'] as String?;
    final String? userId = user?['id'] as String?;

    stdout.writeln('\nuser id:  ${userId ?? '(none)'}');
    stdout.writeln('session:  ${accessToken == null ? 'NONE (email confirmation required)' : 'issued'}');
    stdout.writeln('metadata: ${jsonEncode(user?['user_metadata'])}');

    if (userId == null) {
      stdout.writeln('\nNo user id came back; the trigger row cannot be checked.');
      exitCode = 1;
      return;
    }

    // 2. The profile read `loadProfile` performs immediately after auth. Uses
    //    the publishable key (i.e. the `anon` role), because that is the role
    //    a signed-in client actually runs as under RLS.
    final ({int status, String body}) profile = await _get(
      client,
      '$base/rest/v1/users?select=*&id=eq.$userId',
      accessToken == null
          ? headers
          : <String, String>{...headers, 'Authorization': 'Bearer $accessToken'},
    );
    report('profile read (RLS)', profile.status, profile.body);

    // 3. Sign-in with the same credentials, which is the second half of the
    //    reported failure.
    final ({int status, String body}) signin = await _post(
      client,
      '$auth/token?grant_type=password',
      headers,
      <String, dynamic>{'email': email, 'password': password},
    );
    report('signin', signin.status, signin.body);

    // 4. A deliberately wrong password, to confirm the error string the
    //    mapping in `AuthRepository.reasonFor` keys on is still what GoTrue
    //    returns today.
    final ({int status, String body}) bad = await _post(
      client,
      '$auth/token?grant_type=password',
      headers,
      <String, dynamic>{'email': email, 'password': 'definitely-not-it'},
    );
    report('signin with wrong password', bad.status, bad.body);

    await _removeAccount(userId);
  } finally {
    client.close(force: true);
  }
}

/// Deletes the probe account, cascading to `public.users`.
///
/// A probe that leaves a real account behind is a probe that changes the thing
/// it measures: the next run sees an extra row, and a project whose `auth.users`
/// count is being used to reason about whether anyone has ever registered stops
/// being evidence. Needs `MOAEN_DB_URL`, since GoTrue has no client-callable
/// delete — an account cannot remove itself. The id is printed either way, so a
/// skipped cleanup is actionable rather than silent.
Future<void> _removeAccount(String userId) async {
  final String? dbUrl = Platform.environment['MOAEN_DB_URL'];
  if (dbUrl == null || dbUrl.isEmpty) {
    stdout.writeln(
      '\nMOAEN_DB_URL is not set, so the probe account was left behind. '
      'Delete it with:\n'
      "  delete from auth.users where id = '$userId';",
    );
    return;
  }

  final Connection conn = await Connection.openFromUrl(dbUrl);
  try {
    await conn.execute(
      'delete from auth.users where id = \$1',
      parameters: <Object?>[userId],
    );
    stdout.writeln('\nprobe account $userId removed');
  } on ServerException catch (error) {
    stdout.writeln('\nCOULD NOT REMOVE PROBE ACCOUNT $userId: ${error.message}');
  } finally {
    await conn.close();
  }
}
