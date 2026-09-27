import 'package:flutter_test/flutter_test.dart';
import 'package:moaen/features/inspections/domain/inspection_draft.dart';
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
      'city': 'Cairo',
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
      expect(r.city, 'Cairo');
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

    test('the car description fits on a list row', () {
      expect(buildRequest().carDescription, 'Toyota Corolla 2019');
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

  group('InspectionDraft.budgetAmount', () {
    test('parses a plain amount', () {
      expect(const InspectionDraft(budget: '500').budgetAmount, 500.0);
      expect(const InspectionDraft(budget: '495.50').budgetAmount, 495.5);
    });

    test('tolerates surrounding whitespace', () {
      expect(const InspectionDraft(budget: '  500  ').budgetAmount, 500.0);
    });

    test('rejects a negative amount', () {
      // The schema allows `price >= 0`. A negative budget is not a refund, it is
      // a value the form should never produce.
      expect(const InspectionDraft(budget: '-100').budgetAmount, isNull);
    });

    test('rejects what a person might type mid-edit', () {
      // These are the intermediate states of typing. The field is a string
      // precisely so that they are representable; the question is only whether
      // they parse to something sendable.
      expect(const InspectionDraft(budget: '').budgetAmount, isNull);
      expect(const InspectionDraft(budget: 'abc').budgetAmount, isNull);
      expect(const InspectionDraft(budget: '500 EGP').budgetAmount, isNull);
    });

    test('rejects a trailing bare decimal point', () {
      // `double.tryParse('500.')` returns 500.0, so without an explicit check
      // this would be accepted — and a buyer typing `500.50` who submitted at
      // `500.` would have budgeted 500. Off by a fraction of what they meant,
      // which is the kind of error nobody notices until the invoice.
      expect(const InspectionDraft(budget: '5.').budgetAmount, isNull);
      expect(const InspectionDraft(budget: '500.').budgetAmount, isNull);
      // The completed form is still fine.
      expect(const InspectionDraft(budget: '500.5').budgetAmount, 500.5);
    });

    test('rejects infinity', () {
      expect(const InspectionDraft(budget: 'Infinity').budgetAmount, isNull);
    });
  });

  group('InspectionDraft.toRow', () {
    const InspectionDraft complete = InspectionDraft(
      carMake: '  Toyota ',
      carModel: ' Corolla ',
      carYear: ' 2019 ',
      sellerPhone: ' +201000000001 ',
      sellerLocationAddress: ' 12 Nile Street ',
      city: ' Cairo ',
      clientNotes: '  Seller is impatient.  ',
      budget: ' 500 ',
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
      expect(row['city'], 'Cairo');
      expect(row['price'], 500.0);
      expect(row['client_notes'], 'Seller is impatient.');
    });

    test('omits empty notes rather than sending an empty string', () {
      const InspectionDraft noNotes = InspectionDraft(
        carMake: 'Toyota',
        carModel: 'Corolla',
        carYear: '2019',
        sellerPhone: '+201000000001',
        sellerLocationAddress: '12 Nile Street',
        city: 'Cairo',
        clientNotes: '   ',
        budget: '500',
      );

      // `''` would pass the length check but then read back as a note the buyer
      // wrote, which is not the same as having no note.
      expect(noNotes.toRow('user-1').containsKey('client_notes'), isFalse);
    });
  });

  group('CostEstimate', () {
    test('the total is the sum of its parts', () {
      const CostEstimate e = CostEstimate(inspectionFee: 500, travelFee: 120);
      expect(e.total, 620.0);
    });

    test('formats a whole amount without a trailing .00', () {
      // 500.00 implies a precision the figure does not have.
      expect(CostEstimate.format(500), '500 EGP');
    });

    test('keeps a genuine fractional amount', () {
      expect(CostEstimate.format(495.5), '495.50 EGP');
    });

    test('formats zero', () {
      expect(CostEstimate.format(0), '0 EGP');
    });
  });
}
