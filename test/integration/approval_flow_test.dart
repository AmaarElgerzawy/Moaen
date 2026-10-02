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
       'pending', 199, 'Client A', null)
  ''');

  await db.execute('''
    insert into public.inspection_reports (id, inspection_id)
    values ('$reportForEvidence', '$jobForEvidence')
  ''');
}
