// Moaen (معاين) — the impersonation harness shared by the live RLS suites.
//
// ---------------------------------------------------------------------------
// Why the suites are driven from Dart
// ---------------------------------------------------------------------------
// `supabase test db` is the Supabase-idiomatic way to run a policy suite, but it
// provisions a Docker container. A pgTAP suite is not a usable fallback either:
// pgTAP reports pass/fail by writing TAP to the *server's* stdout, which is not
// capturable over a normal Postgres connection, so a Dart port would silently pass
// regardless of whether any policy actually held. Driving the assertions from Dart
// against the real database produces genuine pass/fail, runs under the project's
// existing `flutter test`, and needs no second container.
//
// ---------------------------------------------------------------------------
// How a persona is impersonated
// ---------------------------------------------------------------------------
// The only honest way to test RLS is to become the user: switch to the
// `authenticated` role and populate request.jwt.claims, which is precisely what
// PostgREST does per request. Asserting from the superuser would bypass RLS
// entirely and prove nothing at all.
//
// ---------------------------------------------------------------------------
// Isolation
// ---------------------------------------------------------------------------
// Everything runs inside one transaction that is never committed, so the fixtures
// roll back and the project is left byte-for-byte as it was. Even a test that
// fails partway leaves nothing behind.

// `expect` rather than a bespoke exception: the harness lives under test/ and is
// only ever constructed by a suite, so a failed assertion surfaces with the
// matcher diff rather than as a stack trace from a throw site nobody recognises.
import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';

/// Drives one connection impersonating each persona in turn.
///
/// [fixtures] installs the rows a suite needs. It is a callback rather than a
/// method because the fixtures are suite-specific and this class is shared: two
/// suites asking the same questions should not be able to drift apart by
/// accident, and neither should own the other's fixture set.
class RlsHarness {
  RlsHarness({this.fixtures});

  /// Provisioning callback, run inside the transaction immediately after `begin`
  /// so it is subject to the same rollback as everything else.
  final Future<void> Function(Connection db)? fixtures;

  Connection? _connection;

  /// The session under test. Non-null between [connect] and [dispose].
  Connection get db => _connection!;

  Future<void> connect(String url) async {
    _connection = await Connection.openFromUrl(url);
    // No auto-commit: the entire suite runs inside this one transaction.
    await db.execute('begin');
    await fixtures?.call(db);
  }

  /// Becomes [uid] as an ordinary signed-in user.
  Future<void> asUser(String uid) => asRole('authenticated', uid: uid);

  /// Becomes [role], optionally as [uid].
  ///
  /// The claims are set before the role, matching the order PostgREST uses.
  Future<void> asRole(String role, {String? uid}) async {
    final String claims = uid == null ? '' : '{"sub":"$uid","role":"$role"}';
    await db.execute(
      "select set_config('request.jwt.claims', \$1, true)",
      parameters: [claims],
    );
    await db.execute(
      "select set_config('role', \$1, true)",
      parameters: [role],
    );
  }

  /// Returns to the session owner with no claims.
  ///
  /// Clearing the claims matters as much as clearing the role: both settings are
  /// transaction-local, so a JWT left in place would keep auth.uid() non-null for
  /// the rest of the transaction and quietly change what the guard triggers do.
  Future<void> asSuperuser() async {
    await db.execute("select set_config('request.jwt.claims', '', true)");
    await db.execute("select set_config('role', 'none', true)");
  }

  /// First column of the first row, or null when the query returns no rows.
  Future<Object?> scalar(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final Result result = await db.execute(sql, parameters: parameters);
    return result.isEmpty ? null : result.first[0];
  }

  /// Number of rows the query returns.
  ///
  /// Deliberately row-based rather than a `select count(*)` wrapper: the
  /// assertions read as "this user sees their own inspections", and wrapping every
  /// statement in a subquery would obscure which table is being counted. Counting a
  /// result that RLS already filtered keeps the test honest, because the database,
  /// not the test, decides what is visible.
  Future<int> count(String sql, [List<Object?> parameters = const []]) async {
    final Result result = await db.execute(sql, parameters: parameters);
    return result.length;
  }

  /// Asserts that [sql] is refused with SQLSTATE [sqlState].
  ///
  /// A statement error inside an explicit transaction aborts the whole
  /// transaction, so the body has to run between a savepoint and its rollback.
  /// ROLLBACK TO SAVEPOINT has to be the very next statement: an aborted
  /// transaction rejects everything else, which is an easy mistake to make here
  /// and produces a confusing 25P02 instead of the real result.
  ///
  /// The session is returned to superuser before the savepoint is released, so a
  /// later failure cannot leave the suite stuck impersonating someone.
  ///
  /// That reset is also the reason a second refusal in the same test must call
  /// [asUser] again: otherwise it would be asserting against the superuser's
  /// privileges, which are wide enough that the statement would be permitted and
  /// the test would fail for the wrong reason. A test that mixes refusals with
  /// permitted writes should call [asUser] at the top of each one regardless.
  ///
  /// **This asserts a refusal, not an absence.** An UPDATE whose `USING` clause
  /// matches nothing is not an error in Postgres — RLS filters the row out and the
  /// statement reports success having changed zero rows. Testing "this buyer cannot
  /// edit another buyer's inspection" with [expectDenied] would therefore pass for
  /// the wrong reason, or fail for a confusing one; assert the value is unchanged
  /// instead.
  Future<void> expectDenied(
    String sql, {
    List<Object?> parameters = const [],
    required String sqlState,
    required String because,
  }) async {
    await db.execute('savepoint expect_denied');
    ServerException? caught;
    try {
      await db.execute(sql, parameters: parameters);
    } on ServerException catch (error) {
      caught = error;
    }
    await db.execute('rollback to savepoint expect_denied');
    // Privileges are restored before the savepoint is released, so a later
    // failure cannot leave the suite stuck impersonating someone.
    await asSuperuser();
    await db.execute('release savepoint expect_denied');

    expect(
      caught,
      isNotNull,
      reason: 'expected the statement to be refused: $because',
    );
    expect(
      caught!.code,
      sqlState,
      reason: 'refused, but for the wrong reason: $because',
    );
  }

  Future<void> dispose() async {
    final Connection? connection = _connection;
    _connection = null;
    if (connection == null) return;
    // Roll back before closing so a hard failure in one test cannot leave the
    // fixtures committed to a shared project.
    try {
      await connection.execute('rollback');
    } on Object {
      // The connection may already be unusable; closing is what matters.
    }
    await connection.close(force: true);
  }
}