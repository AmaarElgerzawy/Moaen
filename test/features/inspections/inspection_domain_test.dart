import 'package:flutter_test/flutter_test.dart';
import 'package:moaen/features/inspections/domain/inspection_draft.dart';
import 'package:moaen/features/inspections/domain/inspection_report.dart';
import 'package:moaen/features/inspections/domain/inspection_request.dart';

import '../../support/fake_inspection_repository.dart';

/// Domain tests for the request model.
///
/// These are the tests that protect the screens from the database's
/// representation. PostgREST's decoding is the least documented part of the
/// stack the app sits on, and the failure mode — a `TypeError` thrown while
/// building a widget — shows up as a red screen rather than as a failed
/// assertion, so it is worth pinning down here.
void main() {
  group('InspectionStatus', () {
    test('maps every wire value', () {
      expect(InspectionStatus.fromName('pending'), InspectionStatus.pending);
      expect(InspectionStatus.fromName('accepted'), InspectionStatus.accepted);
      expect(InspectionStatus.fromName('in_progress'), InspectionStatus.inProgress);
      expect(InspectionStatus.fromName('completed'), InspectionStatus.completed);
      expect(InspectionStatus.fromName('cancelled'), InspectionStatus.cancelled);
    });

    test('round-trips through the wire name', () {
      for (final InspectionStatus s in InspectionStatus.values) {
        expect(InspectionStatus.fromName(s.wireName), s);
      }
    });

    test('an unknown status degrades to pending rather than throwing', () {
      // A server that has added a status this build predates. Throwing would
      // take out the whole list screen; one mislabelled row is the better
      // failure.
      expect(InspectionStatus.fromName('disputed'), InspectionStatus.pending);
      expect(InspectionStatus.fromName(''), InspectionStatus.pending);
    });

    test('isOpen separates work in flight from settled', () {
      expect(InspectionStatus.pending.isOpen, isTrue);
      expect(InspectionStatus.accepted.isOpen, isTrue);
      expect(InspectionStatus.inProgress.isOpen, isTrue);
      expect(InspectionStatus.completed.isOpen, isFalse);
      expect(InspectionStatus.cancelled.isOpen, isFalse);
    });
  });

  group('InspectionRequest.fromRow', () {
    /// The row shape PostgREST returns for a full `select()`.
    Map<String, dynamic> row({
      Object? price = 500.0,
      Object? year = 2019,
      Object? reference = 1001,
      String status = 'pending',
      Object? notes,
    }) => <String, dynamic>{
      'id': 'a1a1a1a1-0000-4000-8000-000000000001',
      'reference_no': reference,
      'client_id': 'user-1',
      'inspector_id': null,
      'car_make': 'Toyota',
      'car_model': 'Corolla',
      'car_year': year,
      'seller_phone': '+201000000001',
      'seller_location_address': '12 Nile Street',
      'city': 'Dammam',
      'inspection_center_name': null,
      'status': status,
      'price': price,
      'client_notes': notes,
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    };

    test('reads a full row', () {
      final InspectionRequest r = InspectionRequest.fromRow(row());

      expect(r.id, 'a1a1a1a1-0000-4000-8000-000000000001');
      expect(r.referenceNo, 1001);
      expect(r.clientId, 'user-1');
      expect(r.inspectorId, isNull);
      expect(r.carMake, 'Toyota');
      expect(r.carModel, 'Corolla');
      expect(r.carYear, 2019);
      expect(r.city, 'Dammam');
      expect(r.status, InspectionStatus.pending);
      expect(r.price, 500.0);
      expect(r.clientNotes, isNull);
    });

    test('reads a numeric price that arrives as an int', () {
      // The realistic case, and the one a `as double` cast throws on.
      // `numeric(12,2)` holding 500.00 serialises as `500`, which Dart's JSON
      // decoder produces as an int.
      final InspectionRequest r = InspectionRequest.fromRow(row(price: 500));
      expect(r.price, 500.0);
    });

    test('reads a numeric price that arrives as a string', () {
      // Some PostgREST configurations serialise numeric as a string to avoid
      // float precision loss. Both have to work or the dashboard crashes on a
      // minority of rows.
      final InspectionRequest r = InspectionRequest.fromRow(row(price: '495.50'));
      expect(r.price, 495.5);
    });

    test('a price of zero is zero, not missing', () {
      final InspectionRequest r = InspectionRequest.fromRow(row(price: 0));
      expect(r.price, 0.0);
    });

    test('reads a numeric year that arrives as a double', () {
      // A `smallint` is an integer, but a JSON number with no fractional part is
      // still an int and one with one is not — `2019.0` must not be read as 2019
      // by truncation of a different value.
      final InspectionRequest r = InspectionRequest.fromRow(row(year: 2019.0));
      expect(r.carYear, 2019);
    });

    test('a missing reference does not throw', () {
      // Would mean the column was added without the migration default. A
      // placeholder keeps the list rendering; the field is not load-bearing
      // enough to take the screen down.
      final InspectionRequest r = InspectionRequest.fromRow(row(reference: null));
      expect(r.referenceNo, 0);
    });

    test('keeps an empty client_notes as an empty string, not null', () {
      // Distinct from absent. The form writes NULL rather than '', so an empty
      // string here means the value came from somewhere else and is worth
      // surfacing rather than silently treating as "no notes".
      final InspectionRequest r = InspectionRequest.fromRow(row(notes: ''));
      expect(r.clientNotes, '');
    });
  });

  group('derived display values', () {
    test('the reference is the MN- handle a buyer reads out', () {
      expect(buildRequest(referenceNo: 1001).reference, 'MN-1001');
      expect(buildRequest(referenceNo: 9920).reference, 'MN-9920');
    });

    test('the car description parenthesises the year', () {
      // The design writes the car as `تويوتا أف جي (2023)` on the report and in
      // the entry form's subtitle, so the year is bracketed rather than run on.
      expect(buildRequest().carDescription, 'Toyota Corolla (2019)');
    });

    test('awaiting-inspector is only the pending state', () {
      expect(buildRequest(status: InspectionStatus.pending).isAwaitingInspector, isTrue);
      expect(
        buildRequest(status: InspectionStatus.accepted).isAwaitingInspector,
        isFalse,
      );
    });
  });

  group('InspectionDraft.year', () {
    test('accepts a year inside the schema bound', () {
      expect(const InspectionDraft(carYear: '2019').year, 2019);
      // The schema's own bounds, not a narrower "plausible" range: a 1950 car is
      // unusual but legal, and the database would accept it.
      expect(const InspectionDraft(carYear: '1950').year, 1950);
      expect(const InspectionDraft(carYear: '2100').year, 2100);
    });

    test('rejects a year outside the schema bound', () {
      expect(const InspectionDraft(carYear: '1949').year, isNull);
      expect(const InspectionDraft(carYear: '2101').year, isNull);
    });

    test('rejects what a person might type that is not a year', () {
      // Arabic-Indic digits look like a number and are not one to `int.parse`.
      // This is the case the create form guards against by re-checking the
      // parsed value after the field validator passes.
      expect(const InspectionDraft(carYear: '٢٠١٩').year, isNull);
      expect(const InspectionDraft(carYear: '2019.5').year, isNull);
      expect(const InspectionDraft(carYear: 'abc').year, isNull);
      expect(const InspectionDraft(carYear: '').year, isNull);
      expect(const InspectionDraft(carYear: '   ').year, isNull);
    });
  });

  group('InspectionDraft.toRow', () {
    const InspectionDraft complete = InspectionDraft(
      carMake: '  Toyota ',
      carModel: ' Corolla ',
      carYear: ' 2019 ',
      sellerPhone: ' +201000000001 ',
      sellerLocationAddress: ' 12 Nile Street ',
      city: ' Dammam ',
      clientNotes: '  Seller is impatient.  ',
    );

    test('produces exactly the columns the table has', () {
      final Map<String, dynamic> row = complete.toRow('user-1');

      expect(
        row.keys.toSet(),
        <String>{
          'client_id',
          'car_make',
          'car_model',
          'car_year',
          'seller_phone',
          'seller_location_address',
          'city',
          'price',
          'client_notes',
        },
        reason: 'An unexpected column is a PostgREST error naming a column that '
            'does not exist; a missing one is a silently NULL field.',
      );
    });

    test('never sends a client-chosen reference', () {
      // Migration 0004's trigger overwrites `reference_no` on insert, so sending
      // it would be pointless even if it were permitted. Leaving it out keeps
      // the client from appearing to control a value it does not.
      expect(complete.toRow('user-1').containsKey('reference_no'), isFalse);
    });

    test('never sends a status', () {
      // The table defaults to 'pending'. A client that sent a status could try to
      // create a request that is already accepted, so the column is not in the
      // insert at all rather than sent as a known-good constant.
      expect(complete.toRow('user-1').containsKey('status'), isFalse);
    });

    test('never sends an inspector', () {
      // Assigning an inspector is what the job board does when someone accepts.
      // A client sending one would be claiming an inspection centre without
      // having gone through the board.
      expect(complete.toRow('user-1').containsKey('inspector_id'), isFalse);
    });

    test('trims text and parses the numbers', () {
      final Map<String, dynamic> row = complete.toRow('user-1');

      expect(row['client_id'], 'user-1');
      expect(row['car_make'], 'Toyota');
      expect(row['car_model'], 'Corolla');
      // An int, not a double: `car_year` is `smallint` and PostgREST will
      // refuse a fractional value.
      expect(row['car_year'], 2019);
      expect(row['seller_phone'], '+201000000001');
      expect(row['seller_location_address'], '12 Nile Street');
      expect(row['city'], 'Dammam');
      // The buyer's own proposal, now collected by the form: `price` is what the
      // buyer offered to pay, and every figure downstream of it — the commission,
      // the inspector's share, the agreed total — is derived from it by the trigger.
      // Asserting the *default* rather than a hand-picked number, because the point
      // is that `toRow` carries [InspectionDraft.budget] through unchanged; a test
      // that hard-coded 500 here would still pass if the column went back to being
      // a platform estimate that happened to match.
      expect(row['price'], complete.budget);
      expect(row['price'], isNot(CostEstimate.standard.total));
      expect(row['client_notes'], 'Seller is impatient.');
    });

    test('omits empty notes rather than sending an empty string', () {
      const InspectionDraft noNotes = InspectionDraft(
        carMake: 'Toyota',
        carModel: 'Corolla',
        carYear: '2019',
        sellerPhone: '+201000000001',
        sellerLocationAddress: '12 Nile Street',
        city: 'Dammam',
        clientNotes: '   ',
      );

      // `''` would pass the length check but then read back as a note the buyer
      // wrote, which is not the same as having no note.
      expect(noNotes.toRow('user-1').containsKey('client_notes'), isFalse);
    });
  });

  group('CostEstimate', () {
    test('the total is the sum of its parts', () {
      const CostEstimate e = CostEstimate(
        centerFee: 320,
        inspectorFee: 150,
        platformFee: 49,
      );
      expect(e.total, 519.0);
    });

    test('a pending centre fee is excluded rather than counted as zero', () {
      // The design shows `199 ر.س + رسوم المركز` while no centre has been chosen.
      // Counting the unknown centre fee as zero would make the total look final.
      const CostEstimate e = CostEstimate();
      expect(e.isCenterFeePending, isTrue);
      expect(e.total, 199.0);
    });

    test('naming a centre fills the total in', () {
      final CostEstimate e = CostEstimate.withCenterFee(300);
      expect(e.isCenterFeePending, isFalse);
      expect(e.total, 499.0);
    });

    test('formats a whole amount without a trailing .00', () {
      // 500.00 implies a precision the figure does not have.
      expect(CostEstimate.format(500), '500 ر.س');
    });

    test('keeps a genuine fractional amount', () {
      expect(CostEstimate.format(495.5), '495.50 ر.س');
    });

    test('formats zero', () {
      expect(CostEstimate.format(0), '0 ر.س');
    });

    test('formats the currency before the figure, as the stats bar does', () {
      // Two forms, because the design uses both: the cost boxes and invoices put
      // the currency after the amount, the stats bar and the fee pills put it
      // before. One formatter would force one of them to be wrong.
      expect(CostEstimate.formatPrefixed(300), 'ر.س 300');
    });

    test('groups thousands so a five-figure budget reads as one number', () {
      // The odometer reading on the report needs the same treatment.
      expect(CostEstimate.format(1500), '1,500 ر.س');
      expect(CostEstimate.amount(516778), '516,778');
    });
  });

  group('ReportSectorScoring', () {
    test('produces the four sectors the A4 prints, in order', () {
      final List<ReportSection> rows = ReportSectorScoring.rows();

      expect(
        rows.map((ReportSection s) => s.ordinal),
        <int>[1, 2, 3, 4],
      );
      expect(
        rows.map((ReportSection s) => s.efficiency),
        <int>[95, 98, 100, 80],
      );
    });

    test('the inspector\'s lower-body text is the only note taken from a person', () {
      // The entry form collects free text for one sector only. If any other
      // sector's note changed with it, the form would be writing sentences on a
      // certified document in a named inspector's name.
      final List<ReportSection> rows = ReportSectorScoring.rows(
        suspensionNote: 'المساعد الخلفي الأيسر يفضل تغييره مستقبلاً.',
      );

      expect(rows[3].notes, 'المساعد الخلفي الأيسر يفضل تغييره مستقبلاً.');
      expect(rows.take(3).map((ReportSection s) => s.notes), everyElement(isNotNull));
    });

    test('a blank lower-body note leaves the sector without one', () {
      // Not an empty string: the column is nullable precisely so "a score and no
      // remark" is expressible, and a report row with `''` reads back as a
      // remark nobody wrote.
      for (final String? blank in <String?>[null, '', '   ']) {
        expect(ReportSectorScoring.rows(suspensionNote: blank)[3].notes, isNull);
      }
    });

    test('the headline is the mean of the sectors, and null without them', () {
      expect(ReportSectorScoring.summary(ReportSectorScoring.rows()), 93);
      // 0 is a claim about a car. No sectors means no figure, not a zero one.
      expect(ReportSectorScoring.summary(<ReportSection>[]), isNull);
    });

    test('the headline is 93 and not the reference\'s 88, deliberately', () {
      // Pinned as its own test because it looks like a bug: the reference's donut
      // prints 88 over sectors that average 93, and the temptation is to "fix" the
      // mean down to 88. A mean is checkable by anyone reading the table; a
      // hardcoded 88 would have to be re-derived every time a sector figure moved.
      // See `ReportSectorScoring.summary`.
      final List<ReportSection> rows = ReportSectorScoring.rows();
      final int total = rows.fold(
        0,
        (int sum, ReportSection s) => sum + s.efficiency,
      );
      expect(total, 373);
      expect((total / rows.length).round(), 93);
    });

    test('the first three sectors do not vary with the form', () {
      // The decision behind `rows()`: the A4's own printed figures, whatever the
      // inspector answered. Nothing on Screen 5 feeds these rows, which is the
      // point — a bar showing a percentage nobody agreed to is a claim attributed
      // to a named inspector.
      expect(
        ReportSectorScoring.rows(suspensionNote: null)
            .take(3)
            .map((ReportSection s) => s.efficiency),
        <int>[95, 98, 100],
      );
      expect(
        ReportSectorScoring.rows(suspensionNote: 'ملاحظة')
            .take(3)
            .map((ReportSection s) => s.efficiency),
        <int>[95, 98, 100],
      );
    });
  });

  group('ReportQualityBand', () {
    test('uses the same cut-offs as the report table', () {
      // Pinned in two places in the design — the headline and the efficiency
      // table's own grade — so the bands are pinned here too. A number that is
      // `ممتاز` on one row must not read `سليم` in the banner above it.
      expect(ReportQualityBand.forPercent(100), ReportQualityBand.excellent);
      expect(ReportQualityBand.forPercent(95), ReportQualityBand.excellent);
      expect(ReportQualityBand.forPercent(94), ReportQualityBand.sound);
      expect(ReportQualityBand.forPercent(90), ReportQualityBand.sound);
      expect(ReportQualityBand.forPercent(89), ReportQualityBand.acceptable);
      expect(ReportQualityBand.forPercent(75), ReportQualityBand.acceptable);
      expect(ReportQualityBand.forPercent(74), ReportQualityBand.needsRepair);
      expect(ReportQualityBand.forPercent(0), ReportQualityBand.needsRepair);
    });
  });
}
