// Moaen (Ù…Ø¹Ø§ÙŠÙ†) â€” verification of the Row Level Security policies in
// supabase/migrations/0002_rls.sql against a live Supabase project.
//
// ---------------------------------------------------------------------------
// Why these run in Dart and not in SQL
// ---------------------------------------------------------------------------
// `supabase test db` is the Supabase-idiomatic way to run a policy suite, but
// it provisions a Docker container and this machine has no Docker. A pgTAP
// suite is not a usable fallback either: pgTAP reports pass/fail by writing
// TAP to the *server's* stdout, which is not capturable over a normal
// Postgres connection, so a Dart port would silently pass regardless of
// whether any policy actually held. Driving the assertions from Dart against
// the real database produces genuine pass/fail, runs under the project's
// existing `flutter test`, and needs no second container.
//
// ---------------------------------------------------------------------------
// How a persona is impersonated
// ---------------------------------------------------------------------------
// The only honest way to test RLS is to become the user: switch to the
// `authenticated` role and populate request.jwt.claims, which is precisely
// what PostgREST does per request. Asserting from the superuser would bypass
// RLS entirely and prove nothing at all.
//
// ---------------------------------------------------------------------------
// Isolation
// ---------------------------------------------------------------------------
// Everything runs inside one transaction that is never committed, so the
// fixtures roll back and the project is left byte-for-byte as it was. Even a
// test that fails partway leaves nothing behind.
@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';

// ---------------------------------------------------------------------------
// Fixture identities. Written as literals rather than generated so that a
// failing assertion can be reproduced by hand in the SQL editor.
// ---------------------------------------------------------------------------

const String clientA = '11111111-1111-4111-8111-111111111111';
const String clientB = '22222222-2222-4222-8222-222222222222';
const String inspectorCairo = '33333333-3333-4333-8333-333333333333';
const String inspectorAlex = '44444444-4444-4444-8444-444444444444';
const String admin = '55555555-5555-4555-8555-555555555555';

/// Cairo, requested by client A, unclaimed.
const String jobCairoForClientA = 'a1a1a1a1-0000-4000-8000-000000000001';

/// Alexandria, requested by client A, unclaimed.
const String jobAlexForClientA = 'a1a1a1a1-0000-4000-8000-000000000002';

/// Cairo, requested by client B, unclaimed.
const String jobCairoForClientB = 'a1a1a1a1-0000-4000-8000-000000000003';

/// Cairo, requested by client A, already assigned to inspectorCairo and in
/// progress. Carries the report and the payment row.
const String jobAssignedToCairo = 'a1a1a1a1-0000-4000-8000-000000000004';

const String reportOnAssignedJob = 'b1b1b1b1-0000-4000-8000-000000000001';
const String paymentOnAssignedJob = 'c1c1c1c1-0000-4000-8000-000000000001';

/// Supabase's SQLSTATE for insufficient_privilege, which is what both a
/// missing table grant and a failed RLS `with check` surface as.
const String insufficientPrivilege = '42501';

/// Postgres' SQLSTATE for check_violation, raised by the state-machine guard
/// in 0001_schema.sql.
const String checkViolation = '23514';

void main() {
  final String? databaseUrl = Platform.environment['MOAEN_DB_URL'];

  // A missing credential is a skip, not a failure: `flutter test` has to stay
  // useful on a machine that has never been pointed at a Supabase project. A
  // credential that is present but wrong is deliberately *not* skipped.
  final String? skipReason = (databaseUrl == null || databaseUrl.isEmpty)
      ? 'MOAEN_DB_URL is not set. Point it at the project to verify the '
            'row level security policies against a live database.'
      : null;

  final _RlsHarness harness = _RlsHarness();

  // Every test below goes through this wrapper rather than `test` directly, so
  // the skip reason is stated once instead of at twenty call sites where a
  // single omission would turn "no credentials" into a null-assertion crash.
  void rlsTest(String description, Future<void> Function() body) {
    test(description, body, skip: skipReason);
  }

  tearDownAll(() => harness.dispose());

  group('row level security', () {
    // setUpAll runs even when every test in the group is skipped, so it has to
    // stand down on its own when there is no credential. Without this guard a
    // developer with no database would see a null-assertion crash in setUpAll
    // instead of a clean skip.
    setUpAll(() async {
      if (databaseUrl == null || databaseUrl.isEmpty) return;
      await harness.connect(databaseUrl);
    });

    group('tenant isolation on users', () {
      rlsTest('a client sees only their own profile row', () async {
        await harness.asUser(clientA);
        expect(await harness.count('select * from public.users'), 1);
      });

      rlsTest("a client cannot read another client's profile", () async {
        await harness.asUser(clientA);
        expect(
          await harness.count(
            'select * from public.users where id = \$1::uuid',
            [clientB],
          ),
          0,
        );
      });

      rlsTest(
        'a client cannot read an inspector role through the users table',
        () async {
          await harness.asUser(clientA);
          // The role is cast to text: a custom Postgres enum arrives as an
          // opaque byte string, and this assertion is about row visibility
          // rather than about decoding the enum.
          final Object? role = await harness.scalar(
            'select role::text from public.users where id = \$1::uuid',
            [inspectorCairo],
          );
          expect(role, isNull);
        },
      );

      rlsTest(
        'a client cannot promote their own account to inspector',
        () async {
          await harness.asUser(clientA);
          // The UPDATE policy allows a user to edit their own row, so this
          // attack passes policy and is stopped only by the users_role_guard
          // trigger. If that trigger were removed this test is the one that
          // would notice.
          await harness.expectDenied(
            'update public.users set role = \'inspector\' where id = \$1::uuid',
            parameters: [clientA],
            sqlState: insufficientPrivilege,
            because:
                'role must not be self-assignable through the profile editor',
          );
        },
      );
    });

    group('admin visibility', () {
      rlsTest('an admin sees every profile row', () async {
        // Impersonated as `authenticated`, not as service_role. service_role
        // carries BYPASSRLS and would see all five rows without a single
        // policy ever being consulted, so testing admin that way would
        // demonstrate nothing. This path actually evaluates
        // current_user_role() = 'admin' in users_select_self_or_admin.
        await harness.asUser(admin);
        expect(await harness.count('select * from public.users'), 5);
      });
    });

    group('public inspector profiles', () {
      rlsTest('the view lists inspectors and excludes private columns', () async {
        await harness.asSuperuser();
        final Result columns = await harness.db.execute(
          "select column_name from information_schema.columns "
          "where table_schema = 'public' and table_name = 'inspector_profiles' "
          'order by ordinal_position',
        );
        expect(columns.map((row) => row[0]), <String>[
          'id',
          'full_name',
          'avatar_url',
          'location_city',
          'rating',
        ]);
      });

      rlsTest(
        'a client can read inspector profiles through the view',
        () async {
          await harness.asUser(clientA);
          // Two inspectors exist, and neither of them is reachable through
          // public.users by this client.
          expect(
            await harness.count('select * from public.inspector_profiles'),
            2,
          );
        },
      );
    });

    group('inspection visibility', () {
      rlsTest(
        "a client sees their own inspections and no one else's",
        () async {
          await harness.asUser(clientA);
          expect(
            await harness.count('select * from public.car_inspections'),
            3,
          );
        },
      );

      rlsTest(
        'a Cairo inspector sees Cairo board jobs and their own job',
        () async {
          await harness.asUser(inspectorCairo);
          // jobCairoForClientA and jobCairoForClientB are pending and in Cairo;
          // jobAssignedToCairo is theirs. jobAlexForClientA is not theirs.
          expect(
            await harness.count('select * from public.car_inspections'),
            3,
          );
        },
      );

      rlsTest('a Cairo inspector sees no Alexandria jobs', () async {
        await harness.asUser(inspectorCairo);
        expect(
          await harness.count(
            "select * from public.car_inspections where city = 'Alexandria'",
          ),
          0,
        );
      });

      rlsTest('an Alexandria inspector sees only the Alexandria job', () async {
        await harness.asUser(inspectorAlex);
        expect(await harness.count('select * from public.car_inspections'), 1);
      });

      rlsTest('an out-of-city inspector has no row to claim', () async {
        await harness.asUser(inspectorAlex);
        // The UPDATE guard in 0001 forces inspector_id := auth.uid() on
        // acceptance. An Alexandria inspector claiming a Cairo job would
        // therefore hand the job to themselves, so the row has to be invisible
        // in the first place. This is the assertion that proves the city
        // scoping holds on the write path, not just on the read path.
        expect(
          await harness.count(
            'select * from public.car_inspections where id = \$1::uuid',
            [jobCairoForClientA],
          ),
          0,
        );
      });
    });

    group('forgery attempts', () {
      rlsTest('a client cannot insert an inspection that is already completed', () async {
        await harness.asUser(clientA);
        await harness.expectDenied(
          'insert into public.car_inspections (client_id, car_make, car_model, '
          "car_year, seller_phone, seller_location_address, city, status, "
          "price) values (\$1::uuid, 'X', 'Y', 2020, '+20100', 'forged st', "
          "'Cairo', 'completed', 1)",
          parameters: [clientA],
          sqlState: insufficientPrivilege,
          because: 'a request must be created pending, unclaimed, by its owner',
        );
      });

      rlsTest('a client cannot open an inspection on behalf of another client', () async {
        await harness.asUser(clientA);
        await harness.expectDenied(
          'insert into public.car_inspections (client_id, car_make, car_model, '
          "car_year, seller_phone, seller_location_address, city, status, "
          "price) values (\$1::uuid, 'X', 'Y', 2020, '+20100', 'forged st', "
          "'Cairo', 'pending', 1)",
          parameters: [clientB],
          sqlState: insufficientPrivilege,
          because: 'client_id must equal the caller',
        );
      });

      rlsTest('a client cannot delete an inspection', () async {
        await harness.asUser(clientA);
        await harness.expectDenied(
          'delete from public.car_inspections where id = \$1::uuid',
          parameters: [jobCairoForClientA],
          sqlState: insufficientPrivilege,
          because:
              'no DELETE policy exists for anyone, so history is preserved',
        );
      });

      rlsTest('a client cannot insert a released payment', () async {
        await harness.asUser(clientA);
        // There is no INSERT grant and no INSERT policy on payments, so this is
        // refused at the privilege layer before any policy is consulted. A
        // client able to do this could settle its own escrow in its favour.
        await harness.expectDenied(
          'insert into public.payments (inspection_id, amount, status, '
          "payment_method, transaction_id) values (\$1::uuid, 1, 'released', "
          "'cash', 'forged-tx')",
          parameters: [jobCairoForClientA],
          sqlState: insufficientPrivilege,
          because:
              'payments are written by a service-role function, never by '
              'a client',
        );
      });

      rlsTest('anon has no access to any table', () async {
        // The migration header claims anon "receives no access at all". With
        // the grant revoked there is nothing to evaluate.
        await harness.asRole('anon');
        await harness.expectDenied(
          'select * from public.users',
          sqlState: insufficientPrivilege,
          because: 'sign-up flows through Supabase Auth, never a table read',
        );
      });
    });

    group('inspection state machine', () {
      rlsTest('an inspection cannot skip from pending to completed', () async {
        await harness.asUser(inspectorCairo);
        await harness.expectDenied(
          "update public.car_inspections set status = 'completed' "
          'where id = \$1::uuid',
          parameters: [jobCairoForClientA],
          sqlState: checkViolation,
          because: 'accepted and in_progress may not be skipped',
        );
      });

      rlsTest(
        'accepting a job assigns it to the accepting inspector',
        () async {
          await harness.asUser(inspectorCairo);
          await harness.db.execute(
            "update public.car_inspections set status = 'accepted' "
            'where id = \$1::uuid',
            parameters: [jobCairoForClientA],
          );
          final Object? inspectorId = await harness.scalar(
            'select inspector_id from public.car_inspections where id = \$1::uuid',
            [jobCairoForClientA],
          );
          expect(inspectorId, inspectorCairo);
        },
      );

      rlsTest(
        'commercial terms are frozen once an inspector is committed',
        () async {
          await harness.asUser(inspectorCairo);
          // jobCairoForClientA is accepted as of the previous test, so it now
          // carries an inspector. Raising the price afterwards would change the
          // agreed amount, which is the reason the guard exists.
          await harness.expectDenied(
            'update public.car_inspections set price = 9999 '
            'where id = \$1::uuid',
            parameters: [jobCairoForClientA],
            sqlState: checkViolation,
            because: 'price is part of the agreement once a job is accepted',
          );
        },
      );
    });

    group('report and payment visibility', () {
      rlsTest('an unrelated client sees no inspection reports', () async {
        await harness.asUser(clientB);
        expect(
          await harness.count('select * from public.inspection_reports'),
          0,
        );
      });

      rlsTest(
        'the paying client sees the payment for their inspection',
        () async {
          await harness.asUser(clientA);
          expect(await harness.count('select * from public.payments'), 1);
        },
      );

      rlsTest('the assigned inspector cannot see the payment record', () async {
        await harness.asUser(inspectorCairo);
        // Deliberate: the inspector does not see the client's payment
        // instrument or transaction id. Payouts get their own tables rather
        // than a widened policy here.
        expect(await harness.count('select * from public.payments'), 0);
      });

      rlsTest('a client cannot write its own inspection report', () async {
        await harness.asUser(clientA);
        await harness.expectDenied(
          'insert into public.inspection_reports (inspection_id, '
          'engine_condition, chassis_condition, paint_body_condition, '
          'transmission_condition, electrical_condition, interior_condition, '
          'overall_rating) values (\$1::uuid, 1, 1, 1, 1, 1, 1, 1)',
          parameters: [jobAssignedToCairo],
          sqlState: insufficientPrivilege,
          because: 'only the assigned inspector authors a report',
        );
      });
    });
  });
}

/// Drives one connection impersonating each persona in turn.
///
/// The transaction is opened once and rolled back on dispose, so the fixtures
/// are never committed to the project.
class _RlsHarness {
  Connection? _connection;

  /// The session under test. Non-null between [connect] and [dispose].
  Connection get db => _connection!;

  Future<void> connect(String url) async {
    _connection = await Connection.openFromUrl(url);
    // No auto-commit: the entire suite runs inside this one transaction.
    await db.execute('begin');
    await _installFixtures();
  }

  /// Provisions the fixture users by inserting into auth.users, so that
  /// handle_new_user() does the work and the provisioning path is exercised
  /// alongside the policies.
  Future<void> _installFixtures() async {
    await db.execute('''
      insert into auth.users (id, email, raw_user_meta_data)
      values
        ('$clientA', 'client_a@test.moaen',
         '{"full_name":"Client A","role":"client","city":"Cairo"}'),
        ('$clientB', 'client_b@test.moaen',
         '{"full_name":"Client B","role":"client","city":"Cairo"}'),
        ('$inspectorCairo', 'inspector_cairo@test.moaen',
         '{"full_name":"Inspector Cairo","role":"inspector","city":"Cairo"}'),
        ('$inspectorAlex', 'inspector_alex@test.moaen',
         '{"full_name":"Inspector Alex","role":"inspector","city":"Alexandria"}'),
        ('$admin', 'admin@test.moaen',
         '{"full_name":"Admin","role":"admin","city":"Cairo"}')
    ''');

    // handle_new_user() whitelists the requested role to client|inspector, so
    // the admin row lands as a client. Promoting it here, as the owner role,
    // is how an administrator would actually create the first admin. The
    // statements that follow are why that promotion is refused for anyone else.
    await db.execute(
      "update public.users set role = 'admin' where id = \$1::uuid",
      parameters: [admin],
    );

    await db.execute('''
      insert into public.car_inspections
        (id, client_id, inspector_id, car_make, car_model, car_year,
         seller_phone, seller_location_address, city, status, price)
      values
        ('$jobCairoForClientA', '$clientA', null,
         'Toyota', 'Corolla', 2019, '+201000000001', '12 Nile St',
         'Cairo', 'pending', 500),
        ('$jobAlexForClientA', '$clientA', null,
         'Kia', 'Cerato', 2021, '+201000000002', '8 Corniche',
         'Alexandria', 'pending', 600),
        ('$jobCairoForClientB', '$clientB', null,
         'Fiat', 'Punto', 2015, '+201000000003', '3 Tahrir',
         'Cairo', 'pending', 400),
        ('$jobAssignedToCairo', '$clientA', '$inspectorCairo',
         'BMW', '320i', 2020, '+201000000004', '5 Zamalek',
         'Cairo', 'in_progress', 900)
    ''');

    await db.execute('''
      insert into public.inspection_reports
        (id, inspection_id, engine_condition, chassis_condition,
         paint_body_condition, transmission_condition, electrical_condition,
         interior_condition, overall_rating)
      values
        ('$reportOnAssignedJob', '$jobAssignedToCairo', 4, 4, 5, 4, 4, 5, 4)
    ''');

    await db.execute('''
      insert into public.payments
        (id, inspection_id, amount, status, payment_method, transaction_id)
      values
        ('$paymentOnAssignedJob', '$jobAssignedToCairo', 900, 'escrow',
         'cash_manual', 'tx-fixture-0001')
    ''');
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
  /// Clearing the claims matters as much as clearing the role: both settings
  /// are transaction-local, so a JWT left in place would keep auth.uid()
  /// non-null for the rest of the transaction and quietly change what the
  /// guard triggers in 0001 do.
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
  /// assertions read as "this user sees their own inspections", and wrapping
  /// every statement in a subquery would obscure which table is being counted.
  /// Counting a result that RLS already filtered keeps the test honest, because
  /// the database, not the test, decides what is visible.
  Future<int> count(String sql, [List<Object?> parameters = const []]) async {
    final Result result = await db.execute(sql, parameters: parameters);
    return result.length;
  }

  /// Asserts that [sql] is refused with SQLSTATE [sqlState].
  ///
  /// A statement error inside an explicit transaction aborts the whole
  /// transaction, so the body has to run between a savepoint and its
  /// rollback. ROLLBACK TO SAVEPOINT has to be the very next statement: an
  /// aborted transaction rejects everything else, which is an easy mistake to
  /// make here and produces a confusing 25P02 instead of the real result.
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
