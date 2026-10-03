// Moaen (معاين) — verification of the approval and report-authoring rules in
// supabase/migrations/0009_approval_and_report_flow.sql against a live project.
//
// ---------------------------------------------------------------------------
// What this suite is for
// ---------------------------------------------------------------------------
// 0009 did three things that together change who may write what on an
// inspection, and each one is a policy or a trigger that only exists to *refuse*
// something. A rule that has never been executed is not a rule:
//
//   1. It widened the buyer's UPDATE policy from `status = 'pending'` to three
//      states, because approval happens after an inspector has accepted and there
//      is no centre or total to approve before then. Under 0002 a buyer literally
//      could not write that approval.
//   2. It froze `client_name` and `inspector_name` onto the request, because RLS
//      keeps an inspector from reading the buyer's row in `public.users`.
//   3. It re-defined `enforce_inspection_transition` to close the holes the wider
//      policy would otherwise open, and relaxed the seven NOT NULL 1-5 ratings
//      that no screen writes.
//
// The widening is the risk. Widening a policy and then separately bolting on
// trigger rules is the classic shape of a migration where the two halves were
// written by different people and tested against each other never. So the bulk of
// this suite is pairs: the write that must succeed, and the write that must be
// refused, one immediately after the other on the same row.
//
// ---------------------------------------------------------------------------
// Relationship to rls_policies_test.dart
// ---------------------------------------------------------------------------
// Separate fixtures, deliberately. That suite's identities are order-dependent —
// one test accepts a job and a later one depends on it being accepted — so a suite
// that mutated those rows would be silently coupled to another file's execution
// order. This one owns its own five inspections and stands alone.
//
// The impersonation harness is shared (test/support/rls_harness.dart): becoming a
// user and rolling back afterwards is one mechanism, and two copies of it would
// be two places for the isolation to be wrong.
@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';

import '../support/rls_harness.dart';

// ---------------------------------------------------------------------------
// Fixture identities and rows.
//
// Written as literals so a failing assertion can be reproduced by hand in the SQL
// editor. Five inspections rather than two, because the rules are about *state*:
// one row per state under test, so no test has to move a row into position for
// the next one and the suite stays order-independent.
// ---------------------------------------------------------------------------

const String clientA = '11111111-1111-4111-8111-111111111111';
const String clientB = '22222222-2222-4222-8222-222222222222';
const String inspectorCairo = '33333333-3333-4333-8333-333333333333';
const String inspectorAlex = '44444444-4444-4444-8444-444444444444';

/// Cairo. Client A's. Unclaimed.
///
/// The self-accept target: rule 3 of the trigger exists for exactly this row.
const String jobPending = 'a2a2a2a2-0000-4000-8000-000000000001';

/// Cairo. Client A's. Accepted by [inspectorCairo], centre booked.
///
/// The buyer's approval target. This is the row 0002's policy could not write.
const String jobAccepted = 'a2a2a2a2-0000-4000-8000-000000000002';

/// Cairo. Client A's. In progress with [inspectorCairo]. No report yet.
const String jobInProgress = 'a2a2a2a2-0000-4000-8000-000000000003';

/// Cairo. Client A's. In progress with [inspectorCairo]. Carries [reportForEvidence].
const String jobForEvidence = 'a2a2a2a2-0000-4000-8000-000000000004';

/// Cairo. Client B's. Unclaimed. The buyer must not be able to write to it.
const String jobOfOtherBuyer = 'a2a2a2a2-0000-4000-8000-000000000005';

/// Cairo. Client A's. Accepted by [inspectorCairo]. Spare, for the cancellation.
///
/// Its own row rather than a third use of [jobAccepted]: `cancelled` is terminal,
/// so a cancel committed here would make every later test on [jobAccepted] fail
/// on the transition table instead of on the rule it means to exercise. That is
/// the whole reason the fixtures carry one inspection per state.
const String jobToCancel = 'a2a2a2a2-0000-4000-8000-000000000006';

/// Cairo. Client A's. Unclaimed. Migration 0010's buyer's-suggestion target.
///
/// Its own row because the rules being tested here are *stateful*: the freeze only
/// fires once an inspector is committed, so the buyer's half must run against a row
/// that is still pending. [jobPending] is pending when this suite starts, but an
/// earlier test accepts it in place, and a rule that passes on one run order and
/// fails on another is not a rule being tested.
const String jobCentreSuggested = 'a2a2a2a2-0000-4000-8000-000000000007';

/// Cairo. Client A's. Unclaimed. Migration 0010's inspector-books target.
///
/// Separate from [jobCentreSuggested] for the same reason: this test drives the row
/// to `accepted`, and the buyer's tests above and below it need it not to be.
const String jobCentreBooked = 'a2a2a2a2-0000-4000-8000-000000000008';

/// The report the evidence rows hang off.
const String reportForEvidence = 'd2d2d2d2-0000-4000-8000-000000000001';

/// The report held by [inspectorSuspended], for the suspension tests.
///
/// [reportForEvidence] would not do: it belongs to an approved inspector on a
/// different job, so a test about a suspended account's own paperwork needs a row
/// that is actually theirs.
const String reportSuspended = 'd2d2d2d2-0000-4000-8000-000000000002';

// ---------------------------------------------------------------------------
// Migration 0011's identities and rows.
//
// Four more people, because 0011 is the first migration whose subject is the
// *person* rather than the inspection: a panel with no administrator in it
// cannot be tested, and a verification gate with no unverified account in it
// cannot be tested either — both of those states are the exception, and an
// exception with no fixture never executes.
// ---------------------------------------------------------------------------

/// The administrator who owns the panel.
///
/// Provisioned by promotion rather than by metadata. `handle_new_user` maps every
/// role except `inspector` to `client`, so an `admin` cannot be minted through
/// `auth.users` at all — which is the right shape for the product (nobody signs
/// themselves up as an administrator) and a trap for a fixture that assumes
/// otherwise. The fixture therefore inserts a client and promotes them with the
/// superuser, which is how an operator does it.
const String adminUser = '55555555-5555-4555-8555-555555555555';

/// Dammam. Inspector. Never approved.
///
/// The queue's raw material, and the account the gate exists for. Dammam because
/// every pending fixture row is there: the board is filtered by the caller's own
/// city, so an unverified inspector placed in a city with no work would pass the
/// gate test for the wrong reason. Distinct from [inspectorCairo] because 0011's
/// `handle_new_user` provisions *every* new inspector unapproved, so the fixture
/// has to approve the ones the 0009 tests rely on and leave this one alone.
const String inspectorUnapproved = '66666666-6666-4666-8666-666666666666';

/// Dammam. Inspector. Approved, then suspended.
///
/// The mid-job suspension, which is the case the assigned arm of
/// `inspections_update_inspector` deliberately stays open for.
const String inspectorSuspended = '77777777-7777-4777-8777-777777777777';

/// A buyer who is suspended.
const String buyerBlocked = '88888888-8888-4888-8888-888888888888';

/// Cairo. Client A's. Unclaimed. 0011's claim-settles-the-budget target.
///
/// Its own row because this test drives it to `accepted`, and the buyer's
/// money-column tests need a row that is still unsettled — the same reason
/// [jobCentreBooked] exists.
const String jobBudgetClaimed = 'a2a2a2a2-0000-4000-8000-000000000010';

/// Cairo. Client A's. Unclaimed. 0011's counter-offer target.
///
/// Sealed by the *first* offer in one test and re-sealed by a second in another,
/// so both need the row to be claimed but un-negotiated. `jobAccepted` would do
/// for the first and not the second.
const String jobCounterOffer = 'a2a2a2a2-0000-4000-8000-000000000011';

/// Cairo. **Client B's.** Unclaimed. Carries the refunded payment.
///
/// Deliberately on the *other* buyer, and that is the entire point of it. The
/// financial overview is asserted twice — once as an admin, who sees four
/// payments, and once as Client A, who must see three — and the two figures differ
/// only by the refund. A refund on Client A's own row would leave both readings
/// identical and the RLS claim untested, since a `security_invoker` view that was
/// in fact running as its owner would still produce the right numbers for a buyer
/// whose rows happen to be all of them.
const String jobRefunded = 'a2a2a2a2-0000-4000-8000-000000000012';

/// Cairo. Client A's. Unclaimed. The verification gate's claim target.
///
/// Its own row for the reason [jobBudgetClaimed] has one: the claim tests assert
/// the row is *still* unclaimed, which a shared row could not survive.
const String jobUnclaimedGate = 'a2a2a2a2-0000-4000-8000-000000000014';

/// Dammam. [buyerBlocked]'s. Unclaimed.
///
/// A suspended account's own job, so "a suspended buyer sees nothing" is a claim
/// about a row they would otherwise be entitled to, rather than about a stranger's.
const String jobBlockedBuyer = 'a2a2a2a2-0000-4000-8000-000000000016';

/// Cairo. Completed, held by [inspectorCairo]. The closed-job offer target.
///
/// `completed` rather than `cancelled`, so the assertion covers the branch that
/// matters: an inspection finished normally, with a report behind it, is the one
/// an inspector is most tempted to keep negotiating on.
const String jobClosed = 'a2a2a2a2-0000-4000-8000-000000000013';

/// Dammam. In progress, held by [inspectorSuspended].
///
/// The mid-job suspension row. Its own row because this one has to stay writable
/// by its assigned inspector *while that inspector is suspended*, and the gate
/// tests would otherwise be asserting against a row another test had moved.
const String jobSuspendedInspector = 'a2a2a2a2-0000-4000-8000-000000000015';

/// A centre the admin panel suspends.
const String centreToBlock = 'c3c3c3c3-0000-4000-8000-000000000001';

/// Supabase's SQLSTATE for insufficient_privilege: a missing table grant, or a
/// failed RLS `with check`.
const String insufficientPrivilege = '42501';

/// Postgres' SQLSTATE for check_violation, which is what
/// `enforce_inspection_transition` raises.
const String checkViolation = '23514';

void main() {
  final String? databaseUrl = Platform.environment['MOAEN_DB_URL'];

  // A missing credential is a skip, not a failure: `flutter test` has to stay
  // useful on a machine that has never been pointed at a Supabase project. A
  // credential that is present but wrong is deliberately *not* skipped.
  final String? skipReason = (databaseUrl == null || databaseUrl.isEmpty)
      ? 'MOAEN_DB_URL is not set. Point it at the project to verify the '
            'approval and report-authoring rules from migration 0009 against a '
            'live database.'
      : null;

  final RlsHarness harness = RlsHarness(fixtures: installApprovalFixtures);

  void approvalTest(String description, Future<void> Function() body) {
    test(description, body, skip: skipReason);
  }

  /// Puts the seeded commission back.
  ///
  /// Registered as a tearDown rather than called at the end of a body, because
  /// `public.platform_settings` is one row on the whole platform and every test in
  /// this file shares one transaction — a body that failed before its restore
  /// would leave 10% in place for everything that ran after it, and the failures
  /// would then be about the wrong number.
  Future<void> restoreCommission() async {
    await harness.asSuperuser();
    await harness.db.execute(
      "update public.platform_settings set commission_type = 'fixed', "
      'commission_value = 49 where id',
    );
  }

  tearDownAll(() => harness.dispose());

  group('the buyer approves', () {
    // setUpAll runs even when every test is skipped, so it has to stand down on
    // its own when there is no credential.
    setUpAll(() async {
      if (databaseUrl == null || databaseUrl.isEmpty) return;
      await harness.connect(databaseUrl);
    });

    group('the write 0009 exists to permit', () {
      approvalTest(
        'a buyer can approve an inspection that has been accepted',
        () async {
          // The test the whole migration was written for. Under 0002 the USING
          // clause was `status = 'pending'`, so this statement was refused with
          // 42501 and the buyer's approval — the button on Screen 1 — could not
          // have worked at all.
          await harness.asUser(clientA);
          await harness.db.execute(
            'update public.car_inspections set client_approved_at = now() '
            'where id = \$1::uuid',
            parameters: [jobAccepted],
          );

          final Object? approved = await harness.scalar(
            'select client_approved_at from public.car_inspections '
            'where id = \$1::uuid',
            [jobAccepted],
          );
          expect(
            approved,
            isNotNull,
            reason: 'the approval must actually be stored, not merely permitted',
          );
        },
      );

      approvalTest('a buyer can still edit an unclaimed request', () async {
        // Regression guard. 0009 widened the policy rather than replacing it, and
        // the "edit my request while it is still unclaimed" behaviour is what the
        // create-then-amend flow depends on.
        await harness.asUser(clientA);
        await harness.db.execute(
          "update public.car_inspections set car_model = 'Camry' "
          'where id = \$1::uuid',
          parameters: [jobPending],
        );

        await harness.asSuperuser();
        expect(
          await harness.scalar(
            'select car_model from public.car_inspections where id = \$1::uuid',
            [jobPending],
          ),
          'Camry',
        );
      });

      approvalTest('a buyer can cancel their own accepted inspection', () async {
        // Rule 3 of the trigger exempts cancellation explicitly. Cancelling is the
        // buyer's own action and the only status write they get; if the widened
        // policy had accidentally closed it, a buyer who changed their mind about
        // an accepted job would be stuck with it forever.
        await harness.asUser(clientA);
        await harness.db.execute(
          "update public.car_inspections set status = 'cancelled' "
          'where id = \$1::uuid',
          parameters: [jobToCancel],
        );

        expect(
          await harness.scalar(
            'select status::text from public.car_inspections '
            'where id = \$1::uuid',
            [jobToCancel],
          ),
          'cancelled',
        );
      });
    });

    // -------------------------------------------------------------------------
    // Every write below was permitted by 0002's policy and must be refused now.
    // They are the reason 0009 replaced the trigger rather than leaving it.
    // -------------------------------------------------------------------------
    group('the writes 0009 exists to refuse', () {
      approvalTest('a buyer cannot accept their own pending inspection', () async {
        // The hole that already existed before 0009, not one it opened. Under the
        // old policy a buyer could update their own pending row, and the state
        // machine permits pending -> accepted, so they could claim their own
        // inspection and become their own inspector. Rule 1 would even have set
        // inspector_id to their own uid.
        await harness.asUser(clientA);
        await harness.expectDenied(
          "update public.car_inspections set status = 'accepted' "
          'where id = \$1::uuid',
          parameters: [jobPending],
          sqlState: checkViolation,
          because: 'only an inspector may accept an inspection',
        );
      });

      approvalTest(
        'a buyer cannot report their own inspection as started',
        () async {
          // The second of the two holes the widened policy would have opened.
          // accepted -> in_progress is a legal transition, so RLS alone would
          // have let a buyer mark their own inspection as under way.
          await harness.asUser(clientA);
          await harness.expectDenied(
            "update public.car_inspections set status = 'in_progress' "
            'where id = \$1::uuid',
            parameters: [jobAccepted],
            sqlState: checkViolation,
            because: 'only an inspector may advance an inspection',
          );
        },
      );

      approvalTest('a buyer cannot assign themselves as the inspector', () async {
        await harness.asUser(clientA);
        await harness.expectDenied(
          'update public.car_inspections set inspector_id = \$1::uuid '
          'where id = \$2::uuid',
          parameters: [clientA, jobAccepted],
          sqlState: checkViolation,
          because: 'a buyer cannot hand their own job to themselves',
        );
      });

      approvalTest(
        "a buyer cannot write the inspector's name on an unclaimed request",
        () async {
          // Note which row: [jobPending]. On an accepted one, rule 2's
          // immutability check would fire first and this test would pass for the
          // wrong reason. The pending row is the only place a buyer is otherwise
          // free to write any column, so it is the only place this needs proving.
          await harness.asUser(clientA);
          await harness.expectDenied(
            "update public.car_inspections set inspector_name = 'Made Up' "
            'where id = \$1::uuid',
            parameters: [jobPending],
            sqlState: checkViolation,
            because:
                'the inspector name attributes a certified report to a person',
          );
        },
      );

      approvalTest('a buyer cannot edit another buyer\u2019s inspection', () async {
        // Not `expectDenied`: an UPDATE whose USING clause matches nothing is not
        // an error in Postgres. RLS filters the row out and the statement reports
        // success having changed zero rows. So the assertion is on the value.
        await harness.asUser(clientA);
        await harness.db.execute(
          "update public.car_inspections set car_model = 'Hijacked' "
          'where id = \$1::uuid',
          parameters: [jobOfOtherBuyer],
        );

        await harness.asSuperuser();
        expect(
          await harness.scalar(
            'select car_model from public.car_inspections where id = \$1::uuid',
            [jobOfOtherBuyer],
          ),
          'Punto',
          reason: 'the row belongs to client B and must be untouched',
        );
      });
    });

    group('the frozen names', () {
      approvalTest('accepting a job freezes the inspector\u2019s name on it', () async {
        // The positive counterpart to the refusal above: the inspector *can* name
        // themselves, and the name has to be the one the buyer will later read off
        // the certified report. Without this the market card and the A4 would have
        // nothing to print.
        await harness.asUser(inspectorCairo);
        await harness.db.execute(
          "update public.car_inspections set status = 'accepted', "
          "inspector_name = 'Karim Adel' where id = \$1::uuid",
          parameters: [jobPending],
        );

        await harness.asSuperuser();
        final Result row = await harness.db.execute(
          'select inspector_id, inspector_name from public.car_inspections '
          'where id = \$1::uuid',
          parameters: [jobPending],
        );
        expect(row.first[0], inspectorCairo);
        expect(row.first[1], 'Karim Adel');
      });

      approvalTest(
        "the requester's name cannot be changed once an inspector is committed",
        () async {
          // Rule 2 includes client_name for a reason that is not historical: the
          // inspector was shown this name on the board when they claimed the job,
          // so changing it afterwards re-attributes the inspection to a name the
          // inspector never agreed to inspect under.
          await harness.asUser(clientA);
          await harness.expectDenied(
            "update public.car_inspections set client_name = 'Someone Else' "
            'where id = \$1::uuid',
            parameters: [jobAccepted],
            sqlState: checkViolation,
            because: 'commercial terms freeze when an inspector is committed',
          );
        },
      );

      approvalTest(
        "the inspector's name cannot be changed after acceptance",
        () async {
          // Run as the *inspector*, not the buyer, so it isolates rule 2 from
          // rule 3. Rule 3 also refuses this write, so testing it as the buyer
          // would prove both rules at once and neither could be deleted without
          // breaking the test.
          await harness.asUser(inspectorCairo);
          await harness.expectDenied(
            "update public.car_inspections set inspector_name = 'Someone Else' "
            'where id = \$1::uuid',
            parameters: [jobAccepted],
            sqlState: checkViolation,
            because: 'a claimed job cannot be re-attributed to another name',
          );
        },
      );
    });

    // ---------------------------------------------------------------------
    // The custom centre columns, migration 0010.
    //
    // Four columns, two parties, one row — which is why this is a trigger and not
    // another policy. Each rule is tested *as the party it is aimed at*, for the
    // reason the inspector-name test above gives: run as the other party, two rules
    // would fire and neither could be removed without a failure.
    // ---------------------------------------------------------------------

    group('the custom centre columns', () {
      approvalTest('a buyer may suggest a centre on their own request', () async {
        // The whole buyer half of the feature. It has to be permitted: the request
        // would be rejected by 0010's shape constraint, which is what makes a name
        // without a coordinate unstorable.
        await harness.asUser(clientA);
        await harness.db.execute(
          'update public.car_inspections set custom_centre_name = \$1, '
          'custom_centre_lat = \$1, custom_centre_lng = \$1 where id = \$1::uuid',
          parameters: ['Al-Amana', 26.4207, 50.0888, jobCentreSuggested],
        );

        await harness.asSuperuser();
        final Result row = await harness.db.execute(
          'select custom_centre_name, custom_centre_lat, custom_centre_lng '
          'from public.car_inspections where id = \$1::uuid',
          parameters: [jobCentreSuggested],
        );
        expect(row.first[0], 'Al-Amana');
        expect(row.first[1], 26.4207);
        expect(row.first[2], 50.0888);
      });

      approvalTest(
        'a buyer may NOT file the centre proof photo',
        () async {
          // Rule 1, and the only field on the whole request that asserts something
          // about a third party. A buyer-filed photo would be read off the report
          // as the inspector's verification that a shop is real, which is the one
          // claim in the document the inspector has not made.
          //
          // Tested on the *pending* row, which is the only row where a buyer is
          // otherwise free to write anything — on an accepted one 0010's rule 2
          // would refuse first and this would pass for the wrong reason.
          await harness.asUser(clientA);
          await harness.expectDenied(
            "update public.car_inspections set "
            "custom_centre_proof_photo_url = 'forged.jpg' "
            'where id = \$1::uuid',
            parameters: [jobCentreSuggested],
            sqlState: checkViolation,
            because: 'the proof photo is the inspector\'s assertion, not the buyer\'s',
          );
        },
      );

      approvalTest(
        'a buyer may NOT file the centre proof photo when creating the request',
        () async {
          // The INSERT half of rule 1, and the reason the trigger guards `insert` as
          // well as `update`. A guard on UPDATE alone leaves the column forgeable
          // from the moment the row exists, because the buyer's own INSERT policy
          // lets them name any column on a row they own.
          await harness.asUser(clientA);
          await harness.expectDenied(
            'insert into public.car_inspections '
            "(id, client_id, car_make, car_model, car_year, seller_phone, "
            "seller_location_address, city, status, price, client_name, "
            'custom_centre_name, custom_centre_lat, custom_centre_lng, '
            'custom_centre_proof_photo_url) values '
            "(\$1::uuid, \$2::uuid, 'Toyota', 'FJ', 2023, '+966500000009', "
            "'Prince Faisal Road', 'Dammam', 'pending', 199, 'Client A', "
            "\$3, 26.4207, 50.0888, 'forged.jpg')",
            parameters: [
              'a2a2a2a2-0000-4000-8000-000000000009',
              clientA,
              'Al-Amana',
            ],
            sqlState: checkViolation,
            because: 'the proof photo is the inspector\'s assertion',
          );
        },
      );

      approvalTest(
        "a buyer's suggested centre freezes once an inspector is committed",
        () async {
          // Rule 2, and the reason the booking box can preselect the buyer's name:
          // an inspector accepts a job on the strength of the centre the buyer
          // named, so that name must not change underneath them afterwards.
          await harness.asUser(clientA);
          await harness.expectDenied(
            "update public.car_inspections set custom_centre_name = 'Elsewhere' "
            'where id = \$1::uuid',
            parameters: [jobAccepted],
            sqlState: checkViolation,
            because: 'the inspector already agreed to inspect at that centre',
          );

          // The coordinate too, in the same write shape. A frozen name over a moved
          // pin is a centre that does not exist.
          await harness.expectDenied(
            'update public.car_inspections set custom_centre_lat = 24.7136 '
            'where id = \$1::uuid',
            parameters: [jobAccepted],
            sqlState: checkViolation,
            because: 'the location freezes with the name',
          );
        },
      );

      approvalTest(
        'the inspector may book an unlisted centre at acceptance',
        () async {
          // The write that has to work and the one rule 2 does *not* cover. If the
          // immutability rule were copied from 0009's without this carve-out, the
          // inspector could never supply a centre on a job they had just claimed,
          // and the feature would be inert for exactly the rows it exists for.
          await harness.asUser(inspectorCairo);
          await harness.db.execute(
            'update public.car_inspections set status = \$1, '
            "inspection_center_name = 'Al-Amana', center_fee = 450, "
            'custom_centre_name = \$1, custom_centre_lat = \$1, '
            'custom_centre_lng = \$1, custom_centre_proof_photo_url = \$1 '
            'where id = \$1::uuid',
            parameters: [
              'accepted',
              'Al-Amana',
              26.4207,
              50.0888,
              'proof.jpg',
              jobCentreBooked,
            ],
          );

          await harness.asSuperuser();
          final Result row = await harness.db.execute(
            'select status, inspection_center_name, center_fee, '
            'custom_centre_name, custom_centre_proof_photo_url '
            'from public.car_inspections where id = \$1::uuid',
            parameters: [jobCentreBooked],
          );
          expect(row.first[0], 'accepted');
          expect(row.first[1], 'Al-Amana');
          expect(row.first[2], 450);
          expect(row.first[3], 'Al-Amana');
          expect(row.first[4], 'proof.jpg');
        },
      );

      approvalTest('a name without a coordinate is not storable', () async {
        // The shape constraint, asserted directly. It is the guarantee the form's
        // completeness check exists to honour, and a form check that stopped
        // matching the database would be worse than no check at all: the request
        // would fail at submit, with a message about a constraint the buyer cannot
        // see.
        await harness.asUser(clientA);
        await harness.expectDenied(
          "update public.car_inspections set custom_centre_name = 'Nowhere' "
          'where id = \$1::uuid',
          parameters: [jobCentreSuggested],
          sqlState: checkViolation,
          because: 'a centre with no location cannot be sent to an inspector',
        );
      });

      approvalTest('a coordinate off the globe is not storable', () async {
        await harness.asUser(clientA);
        await harness.expectDenied(
          'update public.car_inspections set custom_centre_name = \$1, '
          'custom_centre_lat = \$1, custom_centre_lng = \$1 '
          'where id = \$1::uuid',
          parameters: ['Nowhere', 91, 50, jobCentreSuggested],
          sqlState: checkViolation,
          because: 'latitude 91 is not a place on earth',
        );
      });
    });

    group('authoring a report without the seven 1-5 ratings', () {
      approvalTest(
        'the seven superseded ratings are nullable',
        () async {
          // Stated first and as a catalogue query rather than inferred from the
          // inserts below. This is the schema-level claim 0009 makes; the insert
          // tests then prove the policy lets the write through.
          await harness.asSuperuser();
          final Result rows = await harness.db.execute(
            "select column_name from information_schema.columns "
            "where table_schema = 'public' and table_name = 'inspection_reports' "
            "and column_name in ('engine_condition', 'chassis_condition', "
            "'paint_body_condition', 'transmission_condition', "
            "'electrical_condition', 'interior_condition', 'overall_rating') "
            'and is_nullable = \'NO\'',
          );
          expect(
            rows,
            isEmpty,
            reason: 'no screen collects these seven, so NOT NULL would force '
                'every certified document to carry seven invented numbers',
          );
        },
      );

      approvalTest(
        'the assigned inspector can author a report with all seven null',
        () async {
          // The statement the real app issues. Before 0009 this failed with 23502
          // not_null_violation, which is why report entry could not have shipped.
          await harness.asUser(inspectorCairo);
          await harness.db.execute(
            'insert into public.inspection_reports (inspection_id) '
            'values (\$1::uuid)',
            parameters: [jobInProgress],
          );

          await harness.asSuperuser();
          final Result row = await harness.db.execute(
            'select engine_condition, overall_rating, condition_score, '
            'quality_score from public.inspection_reports '
            'where inspection_id = \$1::uuid',
            parameters: [jobInProgress],
          );
          expect(row, hasLength(1), reason: 'exactly one report per inspection');
          // The seven are absent, and the 0007 replacements are too: the form has
          // no input for a headline score either, so a report row must be allowed
          // to exist before anyone computes one.
          for (final Object? value in row.first) {
            expect(value, isNull);
          }
        },
      );

      approvalTest('a buyer still cannot author their own report', () async {
        // Regression. Relaxing the columns relaxed nothing about *who* may write:
        // that is the insert policy, and a buyer able to certify their own
        // inspection would be able to write its verdict.
        await harness.asUser(clientA);
        await harness.expectDenied(
          'insert into public.inspection_reports (inspection_id) '
          'values (\$1::uuid)',
          parameters: [jobInProgress],
          sqlState: insufficientPrivilege,
          because: 'only the assigned inspector authors a report',
        );
      });

      approvalTest('a sector can carry a score and no note', () async {
        // The A4's efficiency table has a note column, and the entry screen has
        // free text for one sector out of four. The check on `notes` would
        // otherwise make the only honest answer — a score with no remark —
        // unreachable, forcing invented prose onto a certified document.
        await harness.asUser(inspectorCairo);
        await harness.db.execute(
          'insert into public.inspection_report_sections '
          '(report_id, ordinal, label, efficiency) values '
          '(\$1::uuid, 2, \$2, 98)',
          parameters: [reportForEvidence, 'ناقل الحركة (القير)'],
        );

        await harness.asSuperuser();
        expect(
          await harness.scalar(
            'select notes from public.inspection_report_sections '
            "where report_id = \$1::uuid and ordinal = 2",
            [reportForEvidence],
          ),
          isNull,
        );
      });

      approvalTest('only the inspector may add a sector', () async {
        await harness.asUser(clientA);
        await harness.expectDenied(
          'insert into public.inspection_report_sections '
          '(report_id, ordinal, label, efficiency) values '
          '(\$1::uuid, 9, \$2, 50)',
          parameters: [reportForEvidence, 'مزروع'],
          sqlState: insufficientPrivilege,
          because: 'a sector is a finding, and findings are the inspector\u2019s',
        );
      });
    });

    group('attaching evidence', () {
      approvalTest('the inspector can attach a photo with no description', () async {
        // What `MediaRepository.attach` issues. `description` is nullable because
        // Screen 5 collects none, and a caption nobody wrote is worse than none.
        await harness.asUser(inspectorCairo);
        await harness.db.execute(
          'insert into public.report_media (report_id, media_url) values '
          '(\$1::uuid, \$2)',
          parameters: [reportForEvidence, 'a2a2a2a2-0000-4000-8000-000000000004/1.jpg'],
        );

        await harness.asSuperuser();
        expect(
          await harness.scalar(
            'select count(*) from public.report_media where report_id = \$1::uuid',
            [reportForEvidence],
          ),
          1,
        );
      });

      approvalTest('an attached photo cannot be deleted or rewritten', () async {
        // Append-only, and enforced at the privilege layer: `grant select, insert`
        // with no update and no delete. Both statements are denied rather than
        // silently matching nothing, so `expectDenied` is the right assertion here.
        await harness.asUser(inspectorCairo);

        await harness.expectDenied(
          'delete from public.report_media where report_id = \$1::uuid',
          parameters: [reportForEvidence],
          sqlState: insufficientPrivilege,
          because: "a report's evidence trail has to be stable",
        );

        // `expectDenied` hands the session back to the superuser so a failure
        // cannot strand the suite impersonating someone, so a second refusal in
        // the same test has to become the inspector again or it would be testing
        // the superuser's privileges.
        await harness.asUser(inspectorCairo);
        await harness.expectDenied(
          'update public.report_media set media_url = \'other.jpg\' '
          'where report_id = \$1::uuid',
          parameters: [reportForEvidence],
          sqlState: insufficientPrivilege,
          because: 'a stored photograph is not something to repoint',
        );
      });

      // FINDING, not a regression. Kept because a test that asserts the wrong
      // behaviour is only safe if it is loudly named and honestly commented.
      approvalTest(
        'FINDING: a buyer CAN attach a photo to their own report',
        () async {
          // The policy is called `report_media_insert_assigned_inspector` and its
          // comment says "only the assigned inspector", but the body checks
          // `is_report_participant(report_id)` — which is true for the *buyer* of
          // that inspection. So a buyer can currently add rows to the attachment
          // list of a document they are handed as evidence.
          //
          // Left as-is rather than fixed here, because this suite's job is to
          // record what the database does. Whether it *should* is a product
          // decision: the counter-argument is real, since a buyer disputing a
          // finding may reasonably want to attach their own photograph. If the
          // decision is "inspector only", this test flips to expectDenied and
          // migration 0010 replaces the `with check` with
          // `is_inspection_inspector((select inspection_id from
          // public.inspection_reports where id = report_id))`.
          await harness.asUser(clientA);
          await harness.db.execute(
            'insert into public.report_media (report_id, media_url) values '
            '(\$1::uuid, \$2)',
            parameters: [reportForEvidence, 'buyer-upload.jpg'],
          );

          expect(
            await harness.count(
              "select * from public.report_media where media_url = 'buyer-upload.jpg'",
            ),
            1,
            reason: 'documents the gap between the policy name and its body',
          );
        },
      );
    });
// ---------------------------------------------------------------------
    // The commission and the negotiation, migration 0011.
    //
    // The same pairing discipline as the groups above: the write that must work,
    // and the write that must be refused, one immediately after the other on the
    // same row. What makes 0011 different is that most of its rules are triggers
    // rather than policies, and a trigger that *corrects* a value is a third
    // outcome this file has to be able to tell apart from both of the others.
    // ---------------------------------------------------------------------

    group('the commission is priced by the database', () {
      approvalTest(
        'a new request is filed with the seeded fee, not a claimed one',
        () async {
          // The statement the real app issues, which names no fee at all. Were the
          // fee a client-written column this row would come back with a null
          // platform_fee, and every figure on the inspector card would be a
          // subtraction from nothing.
          await harness.asUser(clientA);
          await harness.db.execute(
            'insert into public.car_inspections '
            '(id, client_id, car_make, car_model, car_year, seller_phone, '
            'seller_location_address, city, status, price, client_name) values '
            "(\$1::uuid, \$2::uuid, 'Toyota', 'FJ', 2023, '+966500000020', "
            "'Prince Faisal Road', 'Dammam', 'pending', 199, 'Client A')",
            parameters: [
              'a2a2a2a2-0000-4000-8000-000000000020',
              clientA,
            ],
          );

          await harness.asSuperuser();
          final Result row = await harness.db.execute(
            'select platform_fee, inspector_net, agreed_total, bid_status '
            'from public.car_inspections where id = \$1::uuid',
            parameters: ['a2a2a2a2-0000-4000-8000-000000000020'],
          );
          expect(row.first[0], 49, reason: 'the seeded default commission');
          expect(
            row.first[1],
            isNull,
            reason: 'nothing has been agreed, so nothing has been earned',
          );
          expect(row.first[2], isNull);
          expect(row.first[3], 'none');
        },
      );

      approvalTest(
        'a client that names its own fee is corrected rather than obeyed',
        () async {
          // The third outcome, and the reason it needs a test of its own.
          // `enforce_bidding` *overwrites* platform_fee on insert, so the write
          // succeeds and the stored value is the real one. Asserting a refusal
          // would be wrong — there is none — and asserting nothing would leave
          // the shape of the hole untested.
          await harness.asUser(clientA);
          await harness.db.execute(
            'insert into public.car_inspections '
            '(id, client_id, car_make, car_model, car_year, seller_phone, '
            'seller_location_address, city, status, price, client_name, '
            'platform_fee, inspector_net, agreed_total) values '
            "(\$1::uuid, \$2::uuid, 'Toyota', 'FJ', 2023, '+966500000021', "
            "'Prince Faisal Road', 'Dammam', 'pending', 199, 'Client A', "
            '0, 5000, 1)',
            parameters: [
              'a2a2a2a2-0000-4000-8000-000000000021',
              clientA,
            ],
          );

          await harness.asSuperuser();
          final Result row = await harness.db.execute(
            'select platform_fee, inspector_net, agreed_total '
            'from public.car_inspections where id = \$1::uuid',
            parameters: ['a2a2a2a2-0000-4000-8000-000000000021'],
          );
          expect(row.first[0], 49);
          expect(row.first[1], isNull, reason: 'an earnings nobody agreed to');
          expect(row.first[2], isNull);
        },
      );

      approvalTest('the fee is never more than the budget', () async {
        // The guard that makes `budget - fee` arithmetic rather than a debt. A
        // 199 SAR job at a 49 SAR commission is fine; a 20 SAR job at the same
        // commission is not, and clamping is the only answer that neither refuses
        // the buyer's request nor hands the inspector a negative.
        await harness.asUser(clientA);
        await harness.db.execute(
          'insert into public.car_inspections '
          '(id, client_id, car_make, car_model, car_year, seller_phone, '
          'seller_location_address, city, status, price, client_name) values '
          "(\$1::uuid, \$2::uuid, 'Toyota', 'FJ', 2023, '+966500000022', "
          "'Prince Faisal Road', 'Dammam', 'pending', 20, 'Client A')",
          parameters: [
            'a2a2a2a2-0000-4000-8000-000000000022',
            clientA,
          ],
        );

        await harness.asSuperuser();
        expect(
          await harness.scalar(
            'select platform_fee from public.car_inspections '
            'where id = \$1::uuid',
            ['a2a2a2a2-0000-4000-8000-000000000022'],
          ),
          20,
        );
      });

      approvalTest(
        'a percentage commission prices a request differently',
        () async {
          // The other half of `commission_type`, and the reason the fee is a
          // function of the settings row rather than a constant in the app.
          addTearDown(restoreCommission);

          await harness.asUser(adminUser);
          await harness.db.execute(
            "update public.platform_settings set commission_type = 'percent', "
            'commission_value = 10 where id',
          );

          await harness.asUser(clientA);
          await harness.db.execute(
            'insert into public.car_inspections '
            '(id, client_id, car_make, car_model, car_year, seller_phone, '
            'seller_location_address, city, status, price, client_name) values '
            "(\$1::uuid, \$2::uuid, 'Toyota', 'FJ', 2023, '+966500000023', "
            "'Prince Faisal Road', 'Dammam', 'pending', 1000, 'Client A')",
            parameters: [
              'a2a2a2a2-0000-4000-8000-000000000023',
              clientA,
            ],
          );

          await harness.asSuperuser();
          expect(
            await harness.scalar(
              'select platform_fee from public.car_inspections '
              'where id = \$1::uuid',
              ['a2a2a2a2-0000-4000-8000-000000000023'],
            ),
            100,
          );
        },
      );

      approvalTest(
        'a fixed commission larger than the budget is clamped too',
        () async {
          addTearDown(restoreCommission);

          await harness.asUser(adminUser);
          await harness.db.execute(
            'update public.platform_settings set commission_value = 1000 '
            'where id',
          );

          await harness.asUser(clientA);
          await harness.db.execute(
            'insert into public.car_inspections '
            '(id, client_id, car_make, car_model, car_year, seller_phone, '
            'seller_location_address, city, status, price, client_name) values '
            "(\$1::uuid, \$2::uuid, 'Toyota', 'FJ', 2023, '+966500000024', "
            "'Prince Faisal Road', 'Dammam', 'pending', 199, 'Client A')",
            parameters: [
              'a2a2a2a2-0000-4000-8000-000000000024',
              clientA,
            ],
          );

          await harness.asSuperuser();
          expect(
            await harness.scalar(
              'select platform_fee from public.car_inspections '
              'where id = \$1::uuid',
              ['a2a2a2a2-0000-4000-8000-000000000024'],
            ),
            199,
          );
        },
      );

      approvalTest('a commission over 100 percent is not storable', () async {
        // The constraint rather than the clamp. A percentage is a share of
        // something; 150% of a budget is a demand. The settings screen has to
        // refuse it either way, and refusing it here means the refusal is a
        // message at the field rather than a silent ceiling.
        await harness.asUser(adminUser);
        await harness.expectDenied(
          "update public.platform_settings set commission_type = 'percent', "
          'commission_value = 150 where id',
          sqlState: checkViolation,
          because: 'a percentage of a budget cannot exceed the budget',
        );
      });

      approvalTest('a buyer cannot move the commission', () async {
        // Asserted on the value, for the reason the harness documents. The
        // policy's USING clause filters the row out, so the statement succeeds
        // having changed nothing and `expectDenied` would pass for the wrong
        // reason.
        await harness.asUser(clientA);
        await harness.db.execute(
          'update public.platform_settings set commission_value = 0 where id',
        );

        await harness.asSuperuser();
        expect(
          await harness.scalar(
            'select commission_value from public.platform_settings where id',
          ),
          49,
        );
      });

      approvalTest(
        'an administrator moves the commission and the next request follows it',
        () async {
          // The write and its consequence in one test, because the consequence is
          // the point: a setting nobody can move is inert, and a setting that
          // moves without reaching the next row is worse than either.
          addTearDown(restoreCommission);

          await harness.asUser(adminUser);
          await harness.db.execute(
            'update public.platform_settings set commission_value = 75 '
            'where id',
          );

          await harness.asUser(clientA);
          await harness.db.execute(
            'insert into public.car_inspections '
            '(id, client_id, car_make, car_model, car_year, seller_phone, '
            'seller_location_address, city, status, price, client_name) values '
            "(\$1::uuid, \$2::uuid, 'Toyota', 'FJ', 2023, '+966500000025', "
            "'Prince Faisal Road', 'Dammam', 'pending', 500, 'Client A')",
            parameters: [
              'a2a2a2a2-0000-4000-8000-000000000025',
              clientA,
            ],
          );

          await harness.asSuperuser();
          expect(
            await harness.scalar(
              'select platform_fee from public.car_inspections '
              'where id = \$1::uuid',
              ['a2a2a2a2-0000-4000-8000-000000000025'],
            ),
            75,
          );
        },
      );

      approvalTest(
        'a commission that moves does not move the requests already filed',
        () async {
          // The snapshot, and the reason it is one. Without the freeze, moving the
          // commission from 49 to 5 would silently take 44 SAR from every open
          // inspection and hand it back to nobody — the buyer priced their budget
          // against 49 and accepted that number.
          addTearDown(restoreCommission);

          await harness.asUser(adminUser);
          await harness.db.execute(
            'update public.platform_settings set commission_value = 5 where id',
          );

          expect(
            await harness.scalar(
              'select platform_fee from public.car_inspections '
              'where id = \$1::uuid',
              [jobBudgetClaimed],
            ),
            49,
          );
        },
      );
    });

    group('the money columns are written by the rules', () {
      approvalTest('claiming a job settles it at the posted budget', () async {
        // The common case, and the one that needs no negotiation at all: an
        // inspector who is happy with the budget simply claims. Everything about
        // the outcome follows from the budget and the frozen fee, so an inspector
        // who was never asked is not being underpaid.
        await harness.asUser(inspectorCairo);
        await harness.db.execute(
          "update public.car_inspections set status = 'accepted', "
          "inspector_name = 'Karim Adel' where id = \$1::uuid",
          parameters: [jobBudgetClaimed],
        );

        await harness.asSuperuser();
        final Result row = await harness.db.execute(
          'select inspector_id, inspector_net, agreed_total, bid_status, '
          'agreed_at from public.car_inspections where id = \$1::uuid',
          parameters: [jobBudgetClaimed],
        );
        expect(row.first[0], inspectorCairo);
        expect(row.first[1], 150, reason: '199 budget less the 49 fee');
        expect(row.first[2], 199);
        expect(row.first[3], 'agreed');
        expect(row.first[4], isNotNull);
      });

      approvalTest('a buyer cannot write the agreed figures afterwards', () async {
        // The rule the whole commission separation rests on. A buyer who can set
        // `agreed_total` after agreeing can restate the deal after the fact, and
        // the invoice is derived from it.
        await harness.asUser(clientA);
        await harness.expectDenied(
          'update public.car_inspections set agreed_total = 1 '
          'where id = \$1::uuid',
          parameters: [jobBudgetClaimed],
          sqlState: insufficientPrivilege,
          because: 'the agreed amount is a fact, not a field',
        );
      });

      approvalTest(
        'an inspector cannot write the agreed figures either',
        () async {
          // Run as the *inspector*, not the buyer, so the refusal is about the
          // money and not about who owns the row. The mirror case matters more
          // than the first: an inspector who can raise their own agreed net is
          // the failure this whole feature exists to make impossible.
          await harness.asUser(inspectorCairo);
          await harness.expectDenied(
            'update public.car_inspections set inspector_net = 190 '
            'where id = \$1::uuid',
            parameters: [jobBudgetClaimed],
            sqlState: insufficientPrivilege,
            because: 'earnings are settled by the negotiation, not typed in',
          );
        },
      );

      approvalTest(
        'a buyer cannot settle a job with no offer on it',
        () async {
          // The counter-offer branch refuses a response to nothing. Without it a
          // buyer could settle the job at whatever the row already held, which on
          // an unnegotiated request is a budget they may since have forgotten.
          await harness.asUser(clientA);
          await harness.expectDenied(
            "update public.car_inspections set bid_status = 'agreed' "
            'where id = \$1::uuid',
            parameters: [jobCounterOffer],
            sqlState: checkViolation,
            because: 'there is no counter-offer to respond to',
          );
        },
      );

      approvalTest('an inspector cannot move the bid status', () async {
        // `bid_status` is derived — from the claim, from the buyer answer, and
        // from `sync_bid_status` when an offer lands. An inspector who could
        // write it could mark their own counter-offer agreed and skip the buyer.
        await harness.asUser(inspectorCairo);
        await harness.expectDenied(
          "update public.car_inspections set bid_status = 'agreed' "
          'where id = \$1::uuid',
          parameters: [jobCounterOffer],
          sqlState: insufficientPrivilege,
          because: 'only the buyer accepts an offer',
        );
      });
    });

    group('a counter-offer', () {
      /// Files an offer as [inspectorCairo] against [job], keeping [net].
      ///
      /// One helper rather than four copies of the insert: which columns the
      /// client sends is the interesting part of the subject, so every test that
      /// asserts on the stored row has to send the same two.
      Future<void> offer(String job, {required String net}) async {
        await harness.asUser(inspectorCairo);
        await harness.db.execute(
          'insert into public.inspection_bids (inspection_id, net_amount) '
          'values (\$1::uuid, \$2)',
          parameters: [job, net],
        );
        await harness.asSuperuser();
      }

      approvalTest('the net becomes a total through the frozen fee', () async {
        await offer(jobCounterOffer, net: '200');

        final Result row = await harness.db.execute(
          'select net_amount, platform_fee, total_amount, round, status, '
          'inspector_id from public.inspection_bids '
          'where inspection_id = \$1::uuid',
          parameters: [jobCounterOffer],
        );
        expect(row, hasLength(1));
        expect(row.first[0], 200);
        expect(row.first[1], 49, reason: 'the fee the request was filed with');
        expect(row.first[2], 249);
        expect(row.first[3], 1);
        expect(row.first[4], 'pending');
        expect(row.first[5], inspectorCairo);

        // And the inspection knows a negotiation is open, without either screen
        // having to read the offers table to find out.
        expect(
          await harness.scalar(
            'select bid_status from public.car_inspections '
            'where id = \$1::uuid',
            [jobCounterOffer],
          ),
          'pending',
        );
      });

      approvalTest('a buyer cannot counter their own budget', () async {
        // The RLS `with check` is `inspector_id = auth.uid()`, and it is worth
        // having even though `seal_bid` refuses the same write a moment later:
        // the policy is what stops the row existing at all if the trigger is ever
        // loosened, and the trigger is what produces the message.
        await harness.asUser(clientA);
        await harness.expectDenied(
          'insert into public.inspection_bids (inspection_id, net_amount) '
          'values (\$1::uuid, 200)',
          parameters: [jobCounterOffer],
          sqlState: insufficientPrivilege,
          because: 'the buyer does not make offers on their own job',
        );
      });

      approvalTest(
        'a third party cannot quote on a job they do not hold',
        () async {
          // [inspectorAlex] satisfies the policy — they are quoting as
          // themselves — so the only thing standing between them and an offer on
          // another inspector's job is `seal_bid`.
          await harness.asUser(inspectorAlex);
          await harness.expectDenied(
            'insert into public.inspection_bids (inspection_id, net_amount) '
            'values (\$1::uuid, 200)',
            parameters: [jobCounterOffer],
            sqlState: insufficientPrivilege,
            because: 'an offer is a negotiation with one named buyer',
          );
        },
      );

      approvalTest('an offer cannot be filed before the job is claimed', () async {
        // Anyone may take a pending job, so a counter-offer on one is a bid for
        // something nobody has agreed to do.
        await harness.asUser(inspectorCairo);
        await harness.expectDenied(
          'insert into public.inspection_bids (inspection_id, net_amount) '
          'values (\$1::uuid, 200)',
          parameters: [jobUnclaimedGate],
          sqlState: checkViolation,
          because: 'the job is still on the board',
        );
      });

      approvalTest('an offer cannot be filed on a finished job', () async {
        // `completed` rather than `cancelled`, because the request that was
        // inspected normally and produced a report is the one an inspector is
        // most tempted to keep negotiating on.
        await harness.asUser(inspectorCairo);
        await harness.expectDenied(
          'insert into public.inspection_bids (inspection_id, net_amount) '
          'values (\$1::uuid, 200)',
          parameters: [jobClosed],
          sqlState: checkViolation,
          because: 'the inspection is closed',
        );
      });

      approvalTest(
        'a buyer accepts with one word and the amounts come off the offer',
        () async {
          // The whole answer side of the feature. One column is written; the
          // money columns are filled in from the open offer, so a buyer cannot
          // agree to a figure that was never put to them.
          await offer(jobCounterOffer, net: '200');

          await harness.asUser(clientA);
          await harness.db.execute(
            "update public.car_inspections set bid_status = 'agreed' "
            'where id = \$1::uuid',
            parameters: [jobCounterOffer],
          );

          await harness.asSuperuser();
          final Result row = await harness.db.execute(
            'select inspector_net, agreed_total, bid_status, agreed_at '
            'from public.car_inspections where id = \$1::uuid',
            parameters: [jobCounterOffer],
          );
          expect(row.first[0], 200, reason: 'the inspector keeps what they asked');
          expect(row.first[1], 249, reason: 'the buyer pays the total');
          expect(row.first[2], 'agreed');
          expect(row.first[3], isNotNull);

          // And the offer is closed rather than left open forever.
          expect(
            await harness.scalar(
              'select status from public.inspection_bids '
              'where inspection_id = \$1::uuid',
              [jobCounterOffer],
            ),
            'accepted',
          );
        },
      );

      approvalTest(
        'a declined offer closes and the next one is the second round',
        () async {
          // Declining is not a dead end, and the round number is what lets the
          // buyer see that they are being asked again rather than quoted the same
          // figure by a system that did not notice.
          await offer(jobCounterOffer, net: '200');

          await harness.asUser(clientA);
          await harness.db.execute(
            "update public.car_inspections set bid_status = 'declined' "
            'where id = \$1::uuid',
            parameters: [jobCounterOffer],
          );

          await harness.asSuperuser();
          expect(
            await harness.scalar(
              'select inspector_net from public.car_inspections '
              'where id = \$1::uuid',
              [jobCounterOffer],
            ),
            isNull,
            reason: 'a declined offer settles nothing',
          );

          await offer(jobCounterOffer, net: '250');

          final Result rows = await harness.db.execute(
            'select round, net_amount, status from public.inspection_bids '
            'where inspection_id = \$1::uuid order by round',
            parameters: [jobCounterOffer],
          );
          expect(rows, hasLength(2));
          expect(rows[0][0], 1);
          expect(
            rows[0][2],
            'declined',
            reason: 'the refused offer keeps its own history',
          );
          expect(rows[1][0], 2);
          expect(rows[1][1], 250);
          expect(rows[1][2], 'pending');
        },
      );
    });

    group('the verification gate', () {
      approvalTest('an unverified inspector sees an empty board', () async {
        // The requirement as an observation rather than an error: there is
        // nothing to refuse, so the board is simply empty.
        //
        // Stated as two facts rather than one, because "0 rows" on its own is
        // satisfied just as well by a board that happens to be empty. The
        // superuser count is what makes it a claim about the gate: there *is*
        // unclaimed work in this inspector's own city, and they see none of it.
        //
        // Not compared against [inspectorCairo], who is in a different city and
        // would see rows through the participant arm rather than the board — a
        // comparison that looks like it proves the gate while actually proving
        // that Cairo has work on it.
        await harness.asSuperuser();
        expect(
          await harness.count(
            "select * from public.car_inspections "
            "where status = 'pending' and lower(btrim(city)) = 'dammam'",
          ),
          greaterThan(0),
          reason: 'the city has work on it; only the gate can be hiding it',
        );

        await harness.asUser(inspectorUnapproved);
        expect(
          await harness.count('select * from public.car_inspections'),
          0,
          reason: 'same city, same work, one approval apart',
        );
      });

      approvalTest('an unverified inspector cannot claim a job', () async {
        // Asserted on the row rather than with `expectDenied`, for the reason
        // the harness documents: an UPDATE whose USING clause matches nothing is
        // not an error. This statement *would* be permitted by RLS and then
        // refused by the transition trigger, if the row were visible at all.
        await harness.asUser(inspectorUnapproved);
        await harness.db.execute(
          "update public.car_inspections set status = 'accepted', "
          "inspector_name = 'New Arrival' where id = \$1::uuid",
          parameters: [jobUnclaimedGate],
        );

        await harness.asSuperuser();
        final Result row = await harness.db.execute(
          'select status, inspector_id from public.car_inspections '
          'where id = \$1::uuid',
          parameters: [jobUnclaimedGate],
        );
        expect(row.first[0], 'pending');
        expect(row.first[1], isNull);
      });

      approvalTest(
        'a suspended inspector is closed out of the job and its report',
        () async {
          // Uniform, and the correction of an earlier draft of 0011 that claimed
          // otherwise. That draft's comment promised that the assigned arm of
          // `inspections_update_inspector` "stays open" for a suspended inspector
          // so their work is not stranded; the policy said the opposite, because
          // `not current_user_blocked()` sat outside the parenthesised disjunction
          // and closed both arms.
          //
          // The report chain is why the promise was dropped rather than the policy
          // bent: 0011 gated `users`, `car_inspections`, `payments` and
          // `inspection_centres`, and left `inspection_reports`, its parts, its
          // sections and `report_media` on 0002 and 0007's ungated bodies. An
          // inspector who could not move their job could still have written its
          // certified report — findings, efficiency scores, photographs — which is
          // the one thing suspension most obviously has to stop.
          await harness.asUser(inspectorSuspended);
          await harness.db.execute(
            "update public.car_inspections "
            "set counter_note = 'Photos to follow' where id = \$1::uuid",
            parameters: [jobSuspendedInspector],
          );

          expect(
            await harness.count('select * from public.car_inspections'),
            0,
            reason: 'a suspension ends the reads, own row included',
          );
          expect(
            await harness.count('select * from public.inspection_reports'),
            0,
            reason: 'and the report they were halfway through',
          );

          // Asserted on the value rather than with expectDenied: an UPDATE whose
          // USING clause matches nothing reports success having changed zero rows.
          await harness.asSuperuser();
          expect(
            await harness.scalar(
              'select counter_note from public.car_inspections '
              'where id = \$1::uuid',
              [jobSuspendedInspector],
            ),
            isNull,
          );

          await harness.asUser(inspectorSuspended);
          await harness.expectDenied(
            'insert into public.inspection_report_sections '
            '(report_id, ordinal, label, efficiency, notes) '
            "values (\$1::uuid, 0, 'Engine', 80, 'Sound, no leaks')",
            parameters: [reportSuspended],
            sqlState: insufficientPrivilege,
            because: 'a suspended inspector must not certify findings',
          );

          expect(
            await harness.count(
              'select * from public.inspection_report_sections '
              'where report_id = \$1::uuid',
              [reportSuspended],
            ),
            0,
          );
        },
      );

      approvalTest('a suspended buyer sees nothing at all', () async {
        await harness.asUser(buyerBlocked);
        expect(
          await harness.count('select * from public.car_inspections'),
          0,
          reason: 'including the one row they filed themselves',
        );

        await harness.asSuperuser();
        expect(
          await harness.scalar(
            'select status from public.car_inspections where id = \$1::uuid',
            [jobBlockedBuyer],
          ),
          'pending',
          reason: 'the row is there; the account just cannot see it',
        );
      });
    });

    group('only an administrator writes the flags', () {
      approvalTest('a buyer cannot approve themselves', () async {
        // Self-approval is the whole attack. `users_update_self` permits the
        // write — it is their own row — so the refusal has to come from the
        // trigger, which is why 0011 states the rule as a field list rather than
        // as a policy that would have to name every column by hand.
        await harness.asUser(clientA);
        await harness.expectDenied(
          'update public.users set is_approved = false where id = \$1::uuid',
          parameters: [clientA],
          sqlState: insufficientPrivilege,
          because: 'verification is the administrator decision, not the applicant',
        );
      });

      approvalTest('a buyer cannot suspend another account', () async {
        await harness.asUser(clientA);
        await harness.db.execute(
          'update public.users set is_blocked = true where id = \$1::uuid',
          parameters: [clientB],
        );

        await harness.asSuperuser();
        expect(
          await harness.scalar(
            'select is_blocked from public.users where id = \$1::uuid',
            [clientB],
          ),
          false,
        );
      });

      approvalTest('a buyer reads exactly one row of the roster', () async {
        // The exact figure, not a bound. `users_select_self_or_admin` is the only
        // policy that admits a buyer at all, so anything above one is a
        // disclosure and anything below is a broken sign-in.
        await harness.asUser(clientA);
        expect(await harness.count('select * from public.users'), 1);
      });

      approvalTest('an administrator reads the whole roster', () async {
        await harness.asUser(adminUser);
        expect(
          await harness.count('select * from public.users'),
          greaterThanOrEqualTo(8),
          reason: 'two buyers, four inspectors and the administrator',
        );
      });

      approvalTest('an administrator approves, and the mail is queued', () async {
        await harness.asUser(adminUser);
        await harness.db.execute(
          'update public.users set is_approved = true, approved_at = now(), '
          'approved_by = \$1::uuid where id = \$2::uuid',
          parameters: [adminUser, inspectorUnapproved],
        );

        await harness.asSuperuser();
        final Result row = await harness.db.execute(
          "select kind, payload ->> 'email' from public.admin_notifications "
          'where user_id = \$1::uuid',
          parameters: [inspectorUnapproved],
        );
        expect(row, hasLength(1), reason: 'exactly one mail is owed');
        expect(row.first[0], 'inspector_approved');
        expect(row.first[1], 'approval_inspector_new@test.moaen');

        // The queue rather than an immediate send, so an unreachable mail relay
        // cannot fail the approval itself. Asserted by the row still being
        // there: the trigger wrote it in the same transaction as the approval.
        expect(
          await harness.scalar(
            'select delivered_at from public.admin_notifications '
            'where user_id = \$1::uuid',
            [inspectorUnapproved],
          ),
          isNull,
          reason: 'delivery is the edge function job, not the trigger',
        );
      });

      approvalTest('approving twice does not queue a second mail', () async {
        // A re-save is not news. An admin correcting a typo should not re-mail
        // somebody who already knows they were approved.
        await harness.asSuperuser();
        await harness.db.execute(
          'update public.users set approved_at = now() where id = \$1::uuid',
          parameters: [inspectorUnapproved],
        );

        expect(
          await harness.count(
            'select * from public.admin_notifications '
            'where user_id = \$1::uuid',
            [inspectorUnapproved],
          ),
          1,
        );
      });

      approvalTest('a buyer cannot read the notifications queue', () async {
        await harness.asUser(clientA);
        expect(await harness.count('select * from public.admin_notifications'), 0);
      });

      approvalTest('a user may attach their own document', () async {
        // The write the retry control on the restricted screen makes. It has to
        // be permitted for the same reason it is narrow: an account that cannot
        // file its own ID has no way out of the queue.
        await harness.asUser(clientA);
        await harness.db.execute(
          'update public.users set id_photo_url = \$1 where id = \$2::uuid',
          parameters: ['$clientA/id.jpg', clientA],
        );

        await harness.asSuperuser();
        expect(
          await harness.scalar(
            'select id_photo_url from public.users where id = \$1::uuid',
            [clientA],
          ),
          '$clientA/id.jpg',
        );
      });

      approvalTest(
        'nobody may plant a document on another account, an administrator included',
        () async {
          // Deliberate, and the reason the admin arm of `identity_documents_read`
          // has no matching write. An administrator who could file a document on
          // an account could make it look verified by something the holder never
          // held, which would make the whole queue theatre.
          await harness.asUser(adminUser);
          await harness.expectDenied(
            'update public.users set id_photo_url = \$1 where id = \$2::uuid',
            parameters: ['$adminUser/id.jpg', clientA],
            sqlState: insufficientPrivilege,
            because: 'a document has to be filed by the person it describes',
          );
        },
      );
    });

    group('a suspended centre leaves the catalogue', () {
      approvalTest('an administrator suspends a centre and restores it', () async {
        await harness.asUser(adminUser);
        await harness.db.execute(
          'update public.inspection_centres set is_blocked = true '
          'where id = \$1::uuid',
          parameters: [centreToBlock],
        );

        await harness.asUser(clientA);
        expect(
          await harness.count(
            'select * from public.inspection_centres where id = \$1::uuid',
            [centreToBlock],
          ),
          0,
          reason: 'a suspended shop must leave the inspector dropdown',
        );

        await harness.asUser(adminUser);
        expect(
          await harness.count(
            'select * from public.inspection_centres where id = \$1::uuid',
            [centreToBlock],
          ),
          1,
          reason: 'the admin still has to see it in order to unblock it',
        );

        await harness.db.execute(
          'update public.inspection_centres set is_blocked = false '
          'where id = \$1::uuid',
          parameters: [centreToBlock],
        );

        await harness.asUser(clientA);
        expect(
          await harness.count(
            'select * from public.inspection_centres where id = \$1::uuid',
            [centreToBlock],
          ),
          1,
        );
      });

      approvalTest('a buyer cannot suspend a centre', () async {
        await harness.asUser(clientA);
        await harness.db.execute(
          'update public.inspection_centres set is_blocked = true '
          'where id = \$1::uuid',
          parameters: [centreToBlock],
        );

        await harness.asSuperuser();
        expect(
          await harness.scalar(
            'select is_blocked from public.inspection_centres '
            'where id = \$1::uuid',
            [centreToBlock],
          ),
          false,
          reason: 'a centre fee is a price the buyer is shown',
        );
      });
    });

    group('the two admin views', () {
      approvalTest(
        'the financial overview states the money on separate lines',
        () async {
          // The figures, exactly. The view exists so the three amounts cannot be
          // added together by mistake, and an assertion that only checked
          // `collected_volume` would not notice them being conflated.
          await harness.asUser(adminUser);
          final Result row = await harness.db.execute(
            'select collected_volume, platform_revenue, held_in_escrow, '
            'refunded, completed_payments, total_payments '
            'from public.admin_financial_overview',
          );
          expect(row, hasLength(1), reason: 'one row, always');
          expect(row.first[0], 650, reason: '250 plus 400 released');
          expect(row.first[1], 98, reason: 'the fees on those two rows');
          expect(row.first[2], 300, reason: 'held, not earned');
          expect(row.first[3], 150);
          expect(row.first[4], 2);
          expect(row.first[5], 4);
        },
      );

      approvalTest('the financial overview cannot be read sideways', () async {
        // `security_invoker` on the view is what makes this hold. Without it the
        // view would run as its owner, sum every payment on the platform, and hand
        // the total to anyone who could select it — which is every signed-in
        // account, since `grant select ... to authenticated` is table-wide.
        await harness.asUser(clientA);
        final Result row = await harness.db.execute(
          'select collected_volume, held_in_escrow, refunded, total_payments '
          'from public.admin_financial_overview',
        );
        expect(row, hasLength(1), reason: 'the aggregate still returns a row');
        expect(
          row.first[0],
          650,
          reason: 'the two released payments are this buyers own',
        );
        expect(row.first[1], 300);
        expect(
          row.first[2],
          0,
          reason: 'the refund is another buyers and is not in scope here',
        );
        expect(
          row.first[3],
          3,
          reason: 'three of the four payments, and the view must not round that up',
        );
      });

      approvalTest('the order summary totals to what the caller can see', () async {
        // An identity rather than a figure: the fixture rows are moved between
        // states by other tests in this file, so a hard-coded count would make
        // the suite order-dependent for no benefit. What has to hold is that the
        // grouping adds up to the caller's own view of the table.
        await harness.asUser(adminUser);
        final int viaView =
            (await harness.scalar(
              'select sum(orders) from public.admin_order_summary',
            )
                as int?) ??
            0;
        final int viaTable = await harness.count(
          'select * from public.car_inspections',
        );
        expect(viaView, viaTable);

        await harness.asUser(clientA);
        final int buyerViaView =
            (await harness.scalar(
              'select sum(orders) from public.admin_order_summary',
            )
                as int?) ??
            0;
        expect(
          buyerViaView,
          lessThan(viaView),
          reason: 'the summary is subject to the same RLS as the table',
        );
        expect(
          buyerViaView,
          await harness.count('select * from public.car_inspections'),
        );
      });
    });
  });
}

/// Provisions the fixture identities and rows.
///
/// The report insert deliberately states only `inspection_id`, with all seven
/// superseded ratings null. That makes the fixture itself a precondition check: if
/// 0009 were unapplied this would fail with 23502 not_null_violation, which is a
/// louder and more accurate signal than eleven tests failing on a policy that was
/// never going to be consulted.
Future<void> installApprovalFixtures(Connection db) async {
  await db.execute('''
    insert into auth.users (id, email, raw_user_meta_data)
    values
      ('$clientA', 'approval_client_a@test.moaen',
       '{"full_name":"Client A","role":"client","city":"Cairo"}'),
      ('$clientB', 'approval_client_b@test.moaen',
       '{"full_name":"Client B","role":"client","city":"Cairo"}'),
      ('$inspectorCairo', 'approval_inspector_cairo@test.moaen',
       '{"full_name":"Karim Adel","role":"inspector","city":"Cairo"}'),
      ('$inspectorAlex', 'approval_inspector_alex@test.moaen',
       '{"full_name":"Inspector Alex","role":"inspector","city":"Alexandria"}')
  ''');

  // ---- migration 0011's identities
  //
  // Before the inspections, because two of those rows name an inspector and a
  // client that do not exist until these four are provisioned — a foreign key is
  // not a policy and it would refuse the fixture rather than skip a test.
  //
  // Inserted into `auth.users` and so through `handle_new_user`, which under 0011
  // provisions an inspector as `is_approved = false` and a client as
  // `is_approved = true`. That default is the reason the UPDATE below is
  // load-bearing rather than a tidy-up: without it, every 0009 test that claims a
  // job as [inspectorCairo] would fail on the approval gate instead of on the rule
  // it means to exercise, and would pass for the wrong reason once it was fixed.
  await db.execute('''
    insert into auth.users (id, email, raw_user_meta_data)
    values
      ('$adminUser', 'approval_admin@test.moaen',
       '{"full_name":"Platform Admin","role":"client","city":"Riyadh"}'),
      ('$inspectorUnapproved', 'approval_inspector_new@test.moaen',
       '{"full_name":"New Arrival","role":"inspector","city":"Dammam",'
       '"id_photo_url":"66666666-6666-4666-8666-666666666666/id.jpg"}'),
      ('$inspectorSuspended', 'approval_inspector_suspended@test.moaen',
       '{"full_name":"Fallen Karim","role":"inspector","city":"Dammam"}'),
      ('$buyerBlocked', 'approval_client_blocked@test.moaen',
       '{"full_name":"Blocked Buyer","role":"client","city":"Dammam"}')
  ''');

  // Promotion, not metadata. `handle_new_user` maps every role except `inspector`
  // to `client`, so an administrator cannot be minted through `auth.users` — which
  // is right for the product and a trap for a fixture that assumes otherwise. This
  // is how an operator does it, and the only place in the app that does.
  await db.execute('''
    update public.users
       set role = 'admin', is_approved = true, is_blocked = false
     where id = '$adminUser'
  ''');

  await db.execute('''
    update public.users
       set is_approved = true, approved_at = now()
     where id = '$inspectorCairo'
  ''');

  // [inspectorUnapproved] keeps the flag `handle_new_user` gave it, and carries the
  // document it was created with. Stated here rather than left implicit, because a
  // fixture where the unapproved account happens to have no document would make the
  // admin queue's "needs a document" arm untestable for the wrong reason.
  await db.execute('''
    update public.users
       set is_blocked = true, blocked_reason = 'Two disputes unresolved.'
     where id = '$inspectorSuspended'
  ''');

  await db.execute('''
    insert into public.car_inspections
      (id, client_id, inspector_id, car_make, car_model, car_year, seller_phone,
       seller_location_address, city, status, price, client_name, inspector_name)
    values
      ('$jobPending', '$clientA', null,
       'Toyota', 'FJ', 2023, '+966500000001', 'طريق الملك فهد', 'Dammam',
       'pending', 199, 'Client A', null),
      ('$jobAccepted', '$clientA', '$inspectorCairo',
       'Toyota', 'FJ', 2023, '+966500000002', 'طريق الملك فهد', 'Dammam',
       'accepted', 199, 'Client A', 'Karim Adel'),
      ('$jobInProgress', '$clientA', '$inspectorCairo',
       'Toyota', 'FJ', 2023, '+966500000003', 'طريق الملك فهد', 'Dammam',
       'in_progress', 199, 'Client A', 'Karim Adel'),
      ('$jobForEvidence', '$clientA', '$inspectorCairo',
       'Toyota', 'FJ', 2023, '+966500000004', 'طريق الملك فهد', 'Dammam',
       'in_progress', 199, 'Client A', 'Karim Adel'),
      ('$jobOfOtherBuyer', '$clientB', null,
       'Fiat', 'Punto', 2015, '+966500000005', 'شارع التحلية', 'Dammam',
       'pending', 199, 'Client B', null),
      ('$jobToCancel', '$clientA', '$inspectorCairo',
       'Toyota', 'FJ', 2023, '+966500000006', 'طريق الملك فهد', 'Dammam',
       'accepted', 199, 'Client A', 'Karim Adel'),
      ('$jobCentreSuggested', '$clientA', null,
       'Toyota', 'FJ', 2023, '+966500000007', 'طريق الملك فهد', 'Dammam',
       'pending', 199, 'Client A', null),
      ('$jobCentreBooked', '$clientA', null,
       'Toyota', 'FJ', 2023, '+966500000008', 'طريق الملك فهد', 'Dammam',
       'pending', 199, 'Client A', null),
      ('$jobBudgetClaimed', '$clientA', null,
       'Toyota', 'FJ', 2023, '+966500000010', 'طريق الملك فهد', 'Dammam',
       'pending', 199, 'Client A', null),
      ('$jobCounterOffer', '$clientA', '$inspectorCairo',
       'Toyota', 'FJ', 2023, '+966500000011', 'طريق الملك فهد', 'Dammam',
       'accepted', 199, 'Client A', 'Karim Adel'),
      ('$jobRefunded', '$clientB', null,
       'Toyota', 'FJ', 2023, '+966500000012', 'طريق الملك فهد', 'Dammam',
       'pending', 199, 'Client B', null),
      ('$jobUnclaimedGate', '$clientA', null,
       'Toyota', 'FJ', 2023, '+966500000014', 'طريق الملك فهد', 'Dammam',
       'pending', 199, 'Client A', null),
      ('$jobClosed', '$clientA', '$inspectorCairo',
       'Toyota', 'FJ', 2023, '+966500000013', 'طريق الملك فهد', 'Dammam',
       'completed', 199, 'Client A', 'Karim Adel'),
      ('$jobSuspendedInspector', '$clientA', '$inspectorSuspended',
       'Toyota', 'FJ', 2023, '+966500000015', 'طريق الملك فهد', 'Dammam',
       'in_progress', 199, 'Client A', 'Fallen Karim'),
      ('$jobBlockedBuyer', '$buyerBlocked', null,
       'Fiat', 'Punto', 2015, '+966500000016', 'شارع التحلية', 'Dammam',
       'pending', 199, 'Blocked Buyer', null)
  ''');

  // ---- the centre the panel suspends
  //
  // A row of its own rather than a seeded one from 0008: that seed is the
  // catalogue the app ships with, and this suite rolls back, but a named row is
  // what makes the assertion reproducible by hand.
  await db.execute('''
    insert into public.inspection_centres (id, name, city, fee)
    values ('$centreToBlock', 'Al-Amana Dammam', 'Dammam', 350)
    on conflict (id) do nothing
  ''');

  // ---- money for the financial overview
  //
  // Four rows across all three `payment_status` values, because the view's claim
  // is that escrow and refunds are reported *separately* from collected revenue —
  // which cannot be shown by a fixture holding only released payments. The refund
  // sits on a job Client A owns, so the "an admin sees all of it" half and the "a
  // buyer sees only their own" half are two assertions about the same four rows.
  await db.execute('''
    insert into public.payments
      (inspection_id, amount, status, payment_method, transaction_id,
       platform_fee_amount)
    values
      ('$jobInProgress', 250, 'released', 'mada',
       'approval-flow-released-1', 49),
      ('$jobForEvidence', 400, 'released', 'mada',
       'approval-flow-released-2', 49),
      ('$jobToCancel', 300, 'escrow', 'card',
       'approval-flow-escrow-1', null),
      ('$jobRefunded', 150, 'refunded', 'card',
       'approval-flow-refunded-1', null)
    on conflict (inspection_id) do nothing
  ''');

  await db.execute('''
    insert into public.inspection_reports (id, inspection_id)
    values ('$reportForEvidence', '$jobForEvidence')
  ''');

  // A second report, on the suspended inspector's own job, so the suspension tests
  // have something of theirs to be refused. Written by the superuser because that
  // is the only way to give an account paperwork it is not allowed to have.
  await db.execute('''
    insert into public.inspection_reports (id, inspection_id)
    values ('$reportSuspended', '$jobSuspendedInspector')
  ''');
}
