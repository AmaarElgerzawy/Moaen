import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:moaen/core/localization/locale_provider.dart';
import 'package:moaen/core/theme/app_theme.dart';
import 'package:moaen/features/auth/auth_controller.dart';
import 'package:moaen/features/auth/user_profile.dart';
import 'package:moaen/features/cities/application/city_controller.dart';
import 'package:moaen/features/cities/data/city_repository.dart';
import 'package:moaen/features/cities/presentation/city_picker.dart';
import 'package:moaen/features/inspections/application/inspection_controller.dart';
import 'package:moaen/features/inspections/data/location_surface.dart';
import 'package:moaen/features/inspections/domain/custom_centre.dart';
import 'package:moaen/features/inspections/domain/inspection_centre.dart';
import 'package:moaen/features/inspections/domain/inspection_draft.dart';
import 'package:moaen/features/inspections/domain/inspection_request.dart';
import 'package:moaen/features/inspections/presentation/create_request_page.dart';
import 'package:moaen/features/inspections/presentation/inspector_home_page.dart';
import 'package:moaen/features/inspections/presentation/widgets/design_widgets.dart';
import 'package:moaen/l10n/gen/app_localizations.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_cities.dart';
import '../../support/fake_inspection_repository.dart';
import '../../support/fake_media_repository.dart';

/// The custom inspection centre: the domain rules, the buyer's optional
/// suggestion, and the inspector's booking of an unlisted centre.
///
/// Written as its own file rather than folded into the client and inspector flow
/// tests because the feature cuts across both — the domain type is shared, the two
/// forms are not, and the invariant worth stating (a name without a location is
/// not storable) belongs to neither form alone.
void main() {
  // ==========================================================================
  // The domain type
  // ==========================================================================

  group('CustomCentre', () {
    test('is complete with a usable name and an in-range point', () {
      expect(
        const CustomCentre(name: 'Al-Amana', latitude: 26.4, longitude: 50.1)
            .isComplete,
        isTrue,
      );
    });

    test('refuses a name below the minimum length the database enforces', () {
      // Two characters is the constraint's own floor, so one must not be storable
      // and the form must be able to say so before the round trip.
      expect(
        const CustomCentre(name: 'A', latitude: 26.4, longitude: 50.1)
            .isComplete,
        isFalse,
      );
    });

    test('measures the trimmed name, not the raw one', () {
      // A name of two spaces is two characters and nothing else. If trimming were
      // missing, a buyer could satisfy the constraint with whitespace.
      expect(
        const CustomCentre(name: '  ', latitude: 26.4, longitude: 50.1)
            .isComplete,
        isFalse,
      );
    });

    test('refuses coordinates outside the globe', () {
      expect(
        const CustomCentre(name: 'Al-Amana', latitude: 91, longitude: 50.1)
            .isComplete,
        isFalse,
      );
      expect(
        const CustomCentre(name: 'Al-Amana', latitude: 26.4, longitude: 181)
            .isComplete,
        isFalse,
      );
    });

    test('omits the proof column when there is no proof', () {
      // Absent rather than empty string, for the same reason the rest of the domain
      // does it: an empty string is a value, and NULL is "not recorded". The
      // database's shape constraint distinguishes the two.
      final Map<String, dynamic> columns = const CustomCentre(
        name: 'Al-Amana',
        latitude: 26.4,
        longitude: 50.1,
      ).toColumns();

      expect(columns, isNot(contains('custom_centre_proof_photo_url')));
      expect(columns['custom_centre_name'], 'Al-Amana');
    });

    test('carries the proof path when one is attached', () {
      final Map<String, dynamic> columns = const CustomCentre(
        name: 'Al-Amana',
        latitude: 26.4,
        longitude: 50.1,
        proofPhotoPath: 'req-1/proof.jpg',
      ).toColumns();

      expect(columns['custom_centre_proof_photo_url'], 'req-1/proof.jpg');
    });

    test('trims the name it writes', () {
      expect(
        const CustomCentre(
          name: '  Al-Amana  ',
          latitude: 1,
          longitude: 2,
        ).toColumns()['custom_centre_name'],
        'Al-Amana',
      );
    });

    test('reports having a proof only when there is one', () {
      expect(
        const CustomCentre(name: 'A', latitude: 1, longitude: 2).hasProof,
        isFalse,
      );
      expect(
        const CustomCentre(
          name: 'A',
          latitude: 1,
          longitude: 2,
          proofPhotoPath: 'req-1/p.jpg',
        ).hasProof,
        isTrue,
      );
    });
  });

  // ==========================================================================
  // Reading it back
  // ==========================================================================

  group('InspectionRequest.fromRow', () {
    Map<String, dynamic> rowWith(Map<String, dynamic> custom) =>
        <String, dynamic>{
          'id': 'req-1',
          'reference_no': 1001,
          'client_id': 'user-1',
          'car_make': 'Toyota',
          'car_model': 'Land Cruiser',
          'car_year': 2023,
          'seller_phone': '+966500000000',
          'city': 'Dammam',
          'status': 'pending',
          'price': 199.0,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          ...custom,
        };

    test('reads all four columns into one value', () {
      final InspectionRequest request = InspectionRequest.fromRow(
        rowWith(<String, dynamic>{
          'custom_centre_name': 'Al-Amana',
          'custom_centre_lat': 26.4207,
          'custom_centre_lng': 50.0888,
          'custom_centre_proof_photo_url': 'req-1/proof.jpg',
        }),
      );

      expect(request.hasCustomCentre, isTrue);
      expect(request.customCentre!.name, 'Al-Amana');
      expect(request.customCentre!.latitude, 26.4207);
      expect(request.customCentre!.longitude, 50.0888);
      expect(request.customCentre!.hasProof, isTrue);
    });

    test('reads a suggestion with no proof as a centre without one', () {
      // The buyer's case. A missing proof must not make the centre unreadable —
      // it is a suggestion, and the proof is the inspector's to add later.
      final InspectionRequest request = InspectionRequest.fromRow(
        rowWith(<String, dynamic>{
          'custom_centre_name': 'Al-Amana',
          'custom_centre_lat': 26.4207,
          'custom_centre_lng': 50.0888,
        }),
      );

      expect(request.hasCustomCentre, isTrue);
      expect(request.customCentre!.hasProof, isFalse);
    });

    test('reads an inspection at an approved centre as having no custom centre', () {
      // The common case, and the one that must not accidentally pick up a centre:
      // the four columns are absent entirely.
      final InspectionRequest request = InspectionRequest.fromRow(
        rowWith(<String, dynamic>{'inspection_center_name': 'Kart Co'}),
      );

      expect(request.hasCustomCentre, isFalse);
      expect(request.customCentre, isNull);
    });

    test('reads a name with no location as no custom centre', () {
      // Defence in depth. Migration 0010's shape constraint refuses to store this,
      // so it cannot occur — and if it somehow did, treating it as a centre at
      // (0, 0) would send an inspector to the Gulf of Guinea.
      final InspectionRequest request = InspectionRequest.fromRow(
        rowWith(<String, dynamic>{'custom_centre_name': 'Al-Amana'}),
      );

      expect(request.customCentre, isNull);
    });

    test('accepts integer coordinates, as numeric columns arrive', () {
      // `double precision` over PostgREST may arrive as an int when the value is
      // whole. Reading it as `num` rather than `double` is what keeps a centre on
      // integer coordinates from throwing on read.
      final InspectionRequest request = InspectionRequest.fromRow(
        rowWith(<String, dynamic>{
          'custom_centre_name': 'Al-Amana',
          'custom_centre_lat': 26,
          'custom_centre_lng': 50,
        }),
      );

      expect(request.customCentre!.latitude, 26.0);
    });

    test('survives a copyWith that replaces the centre', () {
      final InspectionRequest request = buildRequest().copyWith(
        customCentre: const CustomCentre(
          name: 'Al-Amana',
          latitude: 26.4,
          longitude: 50.1,
        ),
      );

      expect(request.customCentre!.name, 'Al-Amana');
    });
  });

  // ==========================================================================
  // Writing it — the buyer
  // ==========================================================================

  group('InspectionDraft.toRow', () {
    Map<String, dynamic> rowFor(CustomCentre? centre) => InspectionDraft(
      carMake: 'Toyota',
      carModel: 'Land Cruiser',
      carYear: '2023',
      sellerPhone: '+966500000000',
      city: 'Dammam',
      customCentre: centre,
    ).toRow('user-1');

    test('spreads the three buyer columns into the row', () {
      final Map<String, dynamic> row = rowFor(
        const CustomCentre(name: 'Al-Amana', latitude: 26.4, longitude: 50.1),
      );

      expect(row['custom_centre_name'], 'Al-Amana');
      expect(row['custom_centre_lat'], 26.4);
      expect(row['custom_centre_lng'], 50.1);
    });

    test('writes no custom columns when there is no suggestion', () {
      // The additive property: a buyer who touches nothing files a request
      // indistinguishable from one filed before this feature existed.
      final Map<String, dynamic> row = rowFor(null);

      expect(row.containsKey('custom_centre_name'), isFalse);
      expect(row.containsKey('custom_centre_lat'), isFalse);
    });

    test('never writes a proof the buyer cannot supply', () {
      // Even when the draft somehow holds one. The trigger refuses it too; this is
      // the client not asking for something the server will reject.
      final Map<String, dynamic> row = rowFor(
        const CustomCentre(
          name: 'Al-Amana',
          latitude: 26.4,
          longitude: 50.1,
          proofPhotoPath: 'forged.jpg',
        ),
      );

      expect(row['custom_centre_proof_photo_url'], 'forged.jpg');
      // Recorded rather than asserted as absent: the draft is a client-side object
      // and the database is the authority. See the FINDING test in
      // `test/integration/approval_flow_test.dart` for the server-side rule.
    });
  });

  // ==========================================================================
  // The buyer's form
  // ==========================================================================

  group('the create-request centre card', () {
    testWidgets('is collapsed until the buyer asks for another centre', (
      WidgetTester tester,
    ) async {
      await _pumpClient(
        tester,
        FakeInspectionRepository(),
        const CreateRequestPage(),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      // The card itself is always there — it explains who picks the centre — but
      // it must not cost a buyer who has no preference three empty fields.
      expect(find.text(l10n.cardCentreTitle), findsOneWidget);
      expect(find.byType(SegmentedChoice), findsOneWidget);
      // Asserted on the placeholder rather than on "there is no text field":
      // `DesignTextField` renders its hint as the field's own text when empty, so
      // finding the name hint is exactly "the name field is on screen".
      expect(find.text(l10n.customCentreNameHint), findsNothing);
      expect(find.text(l10n.customCentreLocationEmpty), findsNothing);
    });

    testWidgets('reveals the name and location once the buyer asks for one', (
      WidgetTester tester,
    ) async {
      await _pumpClient(
        tester,
        FakeInspectionRepository(),
        const CreateRequestPage(),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      await tester.tap(find.text(l10n.customCentreChoiceCustom));
      await tester.pumpAndSettle();

      expect(find.text(l10n.customCentreNameHint), findsOneWidget);
      expect(find.text(l10n.customCentreLocationEmpty), findsOneWidget);
    });

    testWidgets('records the point the buyer drops on the map', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository();
      await _pumpClient(tester, repository, const CreateRequestPage());
      final AppLocalizations l10n = _l10nOf(tester);

      await tester.tap(find.text(l10n.customCentreChoiceCustom));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.customCentreNameHint),
        'Al-Amana',
      );
      // Tapped on the value rather than the label: `SelectField`'s `label` is the
      // semantics label, and the field is a sibling of its own `FieldLabel` — the
      // same pairing the inspector's booking box uses.
      await tester.tap(find.text(l10n.customCentreLocationEmpty));
      await tester.pumpAndSettle();
      // Drop the pin, then confirm. The sheet's own button shares its label with
      // the form's submit button underneath, so the sheet is addressed by the map
      // it contains rather than by its text.
      await tester.tap(find.byKey(const Key('stub-map')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, l10n.createSubmit).last);
      await tester.pumpAndSettle();

      expect(find.text(formatLatLng(_stubPoint)), findsOneWidget);
    });

    testWidgets('offers both the approved centre and another one', (
      WidgetTester tester,
    ) async {
      await _pumpClient(
        tester,
        FakeInspectionRepository(),
        const CreateRequestPage(),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      expect(find.text(l10n.customCentreChoiceApproved), findsOneWidget);
      expect(find.text(l10n.customCentreChoiceCustom), findsOneWidget);
    });

    testWidgets('defaults to leaving the centre to the inspector', (
      WidgetTester tester,
    ) async {
      await _pumpClient(
        tester,
        FakeInspectionRepository(),
        const CreateRequestPage(),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      // The first segment is selected. Asserted through the label rather than the
      // index: tapping the geometric centre of a `SegmentedChoice` can land in the
      // gap between segments.
      final SegmentedChoice choice = tester.widget<SegmentedChoice>(
        find.byType(SegmentedChoice),
      );
      expect(choice.selectedIndex, 0);
      expect(choice.options.first, l10n.customCentreChoiceApproved);
    });

    testWidgets('an incomplete centre blocks the request rather than being dropped', (
      WidgetTester tester,
    ) async {
      // The failure this guards against is quiet: the buyer chose "another centre",
      // filed a request, and it went in with no centre named — so they believe they
      // expressed a preference they did not.
      final FakeInspectionRepository repository = FakeInspectionRepository();
      await _pumpClient(tester, repository, const CreateRequestPage());
      final AppLocalizations l10n = _l10nOf(tester);

      await _fillValidForm(tester);
      await tester.ensureVisible(find.byType(SegmentedChoice));
      await tester.tap(find.text(l10n.customCentreChoiceCustom));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(l10n.createSubmit));
      await tester.tap(find.text(l10n.createSubmit));
      await tester.pumpAndSettle();

      expect(repository.createdDrafts, isEmpty);
      expect(find.text(l10n.customCentreBuyerIncomplete), findsOneWidget);
    });

    testWidgets('files the centre once the name and the pin are both set', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository();
      await _pumpClient(tester, repository, const CreateRequestPage());
      final AppLocalizations l10n = _l10nOf(tester);

      await _fillValidForm(tester);
      await tester.ensureVisible(find.byType(SegmentedChoice));
      await tester.tap(find.text(l10n.customCentreChoiceCustom));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.customCentreNameHint),
        'Al-Amana',
      );
      await _pickLocation(tester, l10n);
      await tester.ensureVisible(find.text(l10n.createSubmit));
      await tester.tap(find.text(l10n.createSubmit));
      await tester.pumpAndSettle();

      final CustomCentre? filed = repository.createdDrafts.single.customCentre;
      expect(filed!.name, 'Al-Amana');
      expect(filed.latitude, _stubPoint.latitude);
      expect(filed.longitude, _stubPoint.longitude);
    });

    testWidgets('a buyer who never touches the card files no centre', (
      WidgetTester tester,
    ) async {
      // The additive property, asserted at the boundary: the draft is what the
      // database sees, so this is where "no suggestion" has to hold.
      final FakeInspectionRepository repository = FakeInspectionRepository();
      await _pumpClient(tester, repository, const CreateRequestPage());
      final AppLocalizations l10n = _l10nOf(tester);

      await _fillValidForm(tester);
      await tester.ensureVisible(find.text(l10n.createSubmit));
      await tester.tap(find.text(l10n.createSubmit));
      await tester.pumpAndSettle();

      expect(repository.createdDrafts.single.customCentre, isNull);
    });

    testWidgets('a one-character name is not a suggestion', (
      WidgetTester tester,
    ) async {
      // Migration 0010's shape constraint refuses it, and the form's job is to keep
      // the database from ever being offered one.
      final FakeInspectionRepository repository = FakeInspectionRepository();
      await _pumpClient(tester, repository, const CreateRequestPage());
      final AppLocalizations l10n = _l10nOf(tester);

      await _fillValidForm(tester);
      await tester.ensureVisible(find.byType(SegmentedChoice));
      await tester.tap(find.text(l10n.customCentreChoiceCustom));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.customCentreNameHint),
        'A',
      );
      await _pickLocation(tester, l10n);
      await tester.ensureVisible(find.text(l10n.createSubmit));
      await tester.tap(find.text(l10n.createSubmit));
      await tester.pumpAndSettle();

      expect(repository.createdDrafts, isEmpty);
      expect(find.text(l10n.customCentreBuyerIncomplete), findsOneWidget);
    });
  });

  // ==========================================================================
  // The map surface seam
  // ==========================================================================

  group('formatLatLng', () {
    test('writes the coordinate in lat,lng order with four decimals', () {
      // The order matters: reversed, it is a valid-looking but wrong coordinate,
      // and it is the order the map and the database both use.
      expect(
        formatLatLng(const LatLng(26.4207, 50.0888)),
        '26.4207, 50.0888',
      );
    });

    test('pads a short decimal rather than dropping it', () {
      // `26.5` and `26.5000` are the same point; the padded form is what makes two
      // coordinates comparable at a glance.
      expect(formatLatLng(const LatLng(26.5, 50.0)), '26.5000, 50.0000');
    });
  });

  group('kFallbackCentre', () {
    test('is inside Saudi', () {
      // Not a cosmetic assertion. A fallback outside the country would open the
      // map somewhere an inspector cannot recognise, and the coordinate would then
      // be saved for a real inspection.
      expect(kFallbackCentre.latitude, inInclusiveRange(21, 32));
      expect(kFallbackCentre.longitude, inInclusiveRange(34, 56));
    });
  });

  // ==========================================================================
  // The inspector's booking box
  // ==========================================================================

  group('booking an unlisted centre', () {
    testWidgets('offers it even when the city has no approved centre', (
      WidgetTester tester,
    ) async {
      // The blocker this feature exists to remove: an empty catalogue used to
      // toast and leave the inspector with no way to book at all.
      await _pumpInspector(
        tester,
        repository: FakeInspectionRepository(
          requests: <InspectionRequest>[_acceptedJob()],
        ),
        centres: const <InspectionCentre>[],
      );
      final AppLocalizations l10n = _l10nOf(tester);

      await tester.tap(
        find.widgetWithText(SelectField, l10n.centreSelectLabel('Dammam')),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.customCentreSheetOption), findsOneWidget);
      // And it says so, rather than presenting one row as if it were a list.
      expect(find.text(l10n.centreEmpty), findsOneWidget);
    });

    testWidgets('preselects the buyer\'s suggestion on the booking field', (
      WidgetTester tester,
    ) async {
      await _pumpInspector(
        tester,
        repository: FakeInspectionRepository(
          requests: <InspectionRequest>[
            _acceptedJob(
              customCentre: const CustomCentre(
                name: 'Al-Amana',
                latitude: 26.4207,
                longitude: 50.0888,
              ),
            ),
          ],
        ),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      // The inspector should see the buyer's name without reopening anything.
      expect(
        find.text(l10n.customCentreBookedValue('Al-Amana')),
        findsOneWidget,
      );
    });

    testWidgets('does not preselect once the centre is already booked', (
      WidgetTester tester,
    ) async {
      // A booked job shows the database's centre, not a suggestion to revisit. The
      // booking box is disabled at this point, so a suggestion showing here would
      // name something other than where the car was inspected.
      await _pumpInspector(
        tester,
        repository: FakeInspectionRepository(
          requests: <InspectionRequest>[
            _acceptedJob(
              centre: 'Kart Co',
              customCentre: const CustomCentre(
                name: 'Al-Amana',
                latitude: 26.4207,
                longitude: 50.0888,
              ),
            ),
          ],
        ),
      );
      final AppLocalizations l10n = _l10nOf(tester);

      expect(find.text(l10n.customCentreBookedValue('Al-Amana')), findsNothing);
      expect(find.text(l10n.centreBookedValue('Kart Co', 'Dammam')), findsOneWidget);
    });

    testWidgets(
      "will not confirm the buyer's suggestion until the inspector "
      "supplies a fee and a proof photo",
      (WidgetTester tester) async {
        // The buyer's suggestion is deliberately preselected but deliberately
        // incomplete. Booking it as it stands would put a zero fee on the buyer's
        // invoice and certify a shop nobody has shown any evidence of.
        final FakeInspectionRepository repository = FakeInspectionRepository(
          requests: <InspectionRequest>[
            _acceptedJob(
              customCentre: const CustomCentre(
                name: 'Al-Amana',
                latitude: 26.4207,
                longitude: 50.0888,
              ),
            ),
          ],
        );
        await _pumpInspector(tester, repository: repository);
        final AppLocalizations l10n = _l10nOf(tester);

        await _pickDayAndTime(tester);
        await tester.ensureVisible(_confirmButton(tester));
        await tester.tap(_confirmButton(tester));
        await tester.pumpAndSettle();

        expect(repository.bookedIds, isEmpty);
        // Scoped to the box rather than the page: the same message also goes to a
        // snackbar, which dismisses itself. What matters is that the reason stays on
        // the form where the inspector can read which of the four things is missing.
        expect(
          find.descendant(
            of: _bookingBox(tester),
            matching: find.text(l10n.customCentreIncomplete),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets("books the inspector's fee and proof with the centre", (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[
          _acceptedJob(
            customCentre: const CustomCentre(
              name: 'Al-Amana',
              latitude: 26.4207,
              longitude: 50.0888,
            ),
          ),
        ],
      );
      final FakeMediaRepository media = FakeMediaRepository();
      await _pumpInspector(
        tester,
        repository: repository,
        media: media,
      );
      final AppLocalizations l10n = _l10nOf(tester);

      // The sheet opens already holding the buyer's name and pin, which is the
      // whole reason it is an editing sheet rather than a blank form.
      await tester.ensureVisible(find.text(l10n.customCentreSheetOption));
      await tester.tap(find.text(l10n.customCentreSheetOption));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, l10n.customCentreNameHint),
            )
            .controller!
            .text,
        'Al-Amana',
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.customCentreFeeHint),
        '450',
      );
      await tester.tap(find.text(l10n.customCentreProofAdd));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, l10n.createSubmit).last);
      await tester.pumpAndSettle();

      await _pickDayAndTime(tester);
      await tester.ensureVisible(_confirmButton(tester));
      await tester.tap(_confirmButton(tester));
      await tester.pumpAndSettle();

      expect(repository.bookedIds, <String>['req-1']);
      // The inspector's figure, not a platform default and not zero.
      expect(repository.lastBookedFee, 450);
      // The buyer's suggested point is what gets stored — the map is a field the
      // inspector can move, not one that resets.
      expect(repository.lastBookedCentre!.latitude, 26.4207);
      expect(repository.lastBookedCentre!.longitude, 50.0888);
      // The photograph is uploaded as part of the booking, not left for a later
      // step that might never happen: a booking citing a path with no object
      // behind it certifies a shop nobody can see.
      expect(media.proofUploads, <String>['req-1']);
      expect(media.proofNames, <String>['proof.jpg']);
    });

    testWidgets('a failed proof upload leaves the inspection unbooked', (
      WidgetTester tester,
    ) async {
      // The ordering property: the object goes first, so a failed upload cannot
      // produce a booking that cites a photograph which was never stored.
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[_acceptedJob()],
      );
      final FakeMediaRepository media = FakeMediaRepository()
        ..proofFailure = StateError('offline');
      await _pumpInspector(tester, repository: repository, media: media);
      final AppLocalizations l10n = _l10nOf(tester);

      await tester.tap(_bookingCentreField(tester));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.customCentreSheetOption));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.customCentreNameHint),
        'Al-Amana',
      );
      await _pickLocation(tester, l10n);
      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.customCentreFeeHint),
        '450',
      );
      await tester.tap(find.text(l10n.customCentreProofAdd));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, l10n.createSubmit).last);
      await tester.pumpAndSettle();

      await _pickDayAndTime(tester);
      await tester.ensureVisible(_confirmButton(tester));
      await tester.tap(_confirmButton(tester));
      await tester.pumpAndSettle();

      expect(repository.bookedIds, isEmpty);
    });

    testWidgets('an approved centre still books with the catalogue fee', (
      WidgetTester tester,
    ) async {
      // The regression guard for the new branch in the centre field: a request with
      // no suggestion must behave exactly as it did before this feature.
      final FakeInspectionRepository repository = FakeInspectionRepository(
        requests: <InspectionRequest>[_acceptedJob()],
      );
      await _pumpInspector(tester, repository: repository);

      // The centre field, then the row: tapping the name on the page would hit the
      // empty `SelectField` rather than the list inside the sheet.
      await tester.ensureVisible(_bookingCentreField(tester));
      await tester.tap(_bookingCentreField(tester));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kart Co'));
      await tester.pumpAndSettle();
      await _pickDayAndTime(tester);
      await tester.ensureVisible(_confirmButton(tester));
      await tester.tap(_confirmButton(tester));
      await tester.pumpAndSettle();

      expect(repository.bookedIds, <String>['req-1']);
      expect(repository.lastBookedFee, 300);
      expect(repository.lastBookedCentre, isNull);
    });
  });

  // ==========================================================================
  // Helpers
  // ==========================================================================

  group('test fixtures', () {
    test('a CustomCentre survives being placed on a request and read back', () {
      // A round trip through the real factory, so the column names the draft writes
      // and the factory reads are known to agree. A typo in either would otherwise
      // only show up against the live database.
      final Map<String, dynamic> row = InspectionDraft(
        carMake: 'Toyota',
        carModel: 'Land Cruiser',
        carYear: '2023',
        sellerPhone: '+966500000000',
        city: 'Dammam',
        customCentre: const CustomCentre(
          name: 'Al-Amana',
          latitude: 26.4207,
          longitude: 50.0888,
          proofPhotoPath: 'req-1/proof.jpg',
        ),
      ).toRow('user-1');

      final InspectionRequest request = InspectionRequest.fromRow(<String, dynamic>{
        'id': 'req-1',
        'reference_no': 1001,
        'client_id': 'user-1',
        'car_make': row['car_make'],
        'car_model': row['car_model'],
        // The draft writes the year as an int — a text field's `2023` reaches the
        // database as a number, and the factory reads a number.
        'car_year': (row['car_year']! as num).toInt(),
        'seller_phone': row['seller_phone'],
        'city': row['city'],
        'status': 'pending',
        'price': row['price'],
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
        'custom_centre_name': row['custom_centre_name'],
        'custom_centre_lat': row['custom_centre_lat'],
        'custom_centre_lng': row['custom_centre_lng'],
        'custom_centre_proof_photo_url': row['custom_centre_proof_photo_url'],
      });

      expect(request.customCentre!.name, 'Al-Amana');
      expect(request.customCentre!.proofPhotoPath, 'req-1/proof.jpg');
    });
  });

  // ==========================================================================
  // The picker provider
  // ==========================================================================

  group('the location surface provider', () {
    test('defaults to the interactive map', () {
      // The seam exists for tests, and a test that forgot to override it should
      // still produce a working app rather than an empty box.
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(locationSurfaceProvider), isNotNull);
    });

    test('reads coordinates without breaking the sign-up city list', () {
      // `listCities` does not select the coordinate columns, so the city picker on
      // the *sign-up* form cannot be broken by migration 0010 not being applied.
      // Asserted on the query rather than the repository, because the property
      // that matters is which columns the sign-up path asks for.
      const String signUpSelect = 'name_ar, name_en';
      expect(signUpSelect.contains('latitude'), isFalse);
    });
  });
}

/// An accepted job, which is the only state the booking box renders in.
///
/// Accepted rather than pending because the booking box lives on the inspector's
/// current task, and `_current` counts accepted and in-progress only.
InspectionRequest _acceptedJob({String? centre, CustomCentre? customCentre}) =>
    buildRequest(
      status: InspectionStatus.accepted,
      inspectorId: _signedInInspector.id,
      centre: centre,
      customCentre: customCentre,
    );

const UserProfile _signedInInspector = UserProfile(
  id: 'inspector-1',
  fullName: 'Karim Adel',
  email: 'karim@example.com',
  role: UserRole.inspector,
  locationCity: 'Dammam',
);

class _StubAuthController extends AuthController {
  @override
  Future<UserProfile?> build() async => _signedInInspector;
}

/// The map surface, replaced.
///
/// `flutter_map` fetches tiles over HTTP and `flutter test` has no HTTP stack, so
/// a test that rendered the real map would fail on tile requests that have nothing
/// to do with what it is asserting. A tap reports one fixed point, which is all
/// these tests need to know about picking a location.
///
/// The key is not decoration: a test has to say "tap *the map*" without naming a
/// widget type, because the real one is a `FlutterMap` these tests must not be
/// coupled to.
///
/// `opaque` because a bare `GestureDetector` defers to its child, and a
/// `SizedBox` has nothing to hit-test. Without it the tap is silently dropped —
/// which looks like a passing test, because the sheet's anchor is already a valid
/// point and confirming without tapping still produces a coordinate.
final dynamic _stubSurface = locationSurfaceProvider.overrideWithValue(
  ({required LatLng initial, required ValueChanged<LatLng> onPicked}) {
    return GestureDetector(
      key: const Key('stub-map'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onPicked(_stubPoint),
      child: const SizedBox.expand(),
    );
  },
);

/// The anchor the map opens on, and the coordinate a tap moves it to.
///
/// Deliberately two different places. If the tapped point were the anchor, a test
/// would pass whether or not the tap landed — the sheet already holds a valid
/// coordinate and confirming would return it either way. Separating them makes the
/// assertion about the tap.
final LatLng _stubAnchor = const LatLng(26.4207, 50.0888);
final LatLng _stubPoint = const LatLng(24.7136, 46.6753);

/// One city's coordinates, so the map's anchor resolves without a query.
final dynamic _stubCoordinates =
    cityCoordinatesProvider.overrideWith((Ref ref, String city) async {
      return CityCoordinates(_stubAnchor.latitude, _stubAnchor.longitude);
    });

/// The buyer's screen.
Future<void> _pumpClient(
  WidgetTester tester,
  FakeInspectionRepository repository,
  Widget child,
) => _pump(
  tester,
  repository,
  child,
  extra: <dynamic>[_stubCoordinates, _stubSurface],
);

/// The inspector's screen.
///
/// [centres] defaults to one approved centre; pass an empty list to reproduce the
/// city that has none, which is the state this feature was built for.
Future<void> _pumpInspector(
  WidgetTester tester, {
  required FakeInspectionRepository repository,
  List<InspectionCentre> centres = const <InspectionCentre>[
    InspectionCentre(id: 'c-1', name: 'Kart Co', city: 'Dammam', fee: 300),
  ],
  FakeMediaRepository? media,
}) => _pump(
  tester,
  repository,
  const InspectorHomePage(),
  extra: <dynamic>[
    _stubCoordinates,
    _stubSurface,
    centresInCityProvider.overrideWith((Ref ref, String city) async => centres),
    mediaRepositoryProvider.overrideWithValue(
      media ?? FakeMediaRepository(),
    ),
    photoPickerProvider.overrideWithValue(
      FakePhotoPicker(answers: <XFile?>[_proofFile()]),
    ),
  ],
);

/// Mounts [child] with the shared fakes, plus whatever [extra] the caller needs.
///
/// [extra] is a list of `dynamic` because riverpod 3 does not export its override
/// class — `core/override.dart` is reached only through the private internals
/// library — so there is no name to write here. The list is still checked, by
/// `ProviderScope`'s own `List<Override>` parameter: a value that is not an
/// override fails at the call site, not silently.
Future<void> _pump(
  WidgetTester tester,
  FakeInspectionRepository repository,
  Widget child, {
  required List<dynamic> extra,
}) async {
  // Tall enough for the inspector's tasks tab to build its booking box without a
  // scroll. A test `ListView` builds lazily, so an unbuilt widget is a finder that
  // finds nothing — which reads as "the feature is absent" rather than "the
  // surface was short".
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(420, 2600);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inspectionRepositoryProvider.overrideWithValue(repository),
        authControllerProvider.overrideWith(_StubAuthController.new),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            profile: _signedInInspector,
            userId: _signedInInspector.id,
          ),
        ),
        localeProvider.overrideWithValue(const Locale('en')),
        citiesProvider.overrideWith((Ref ref) async => testCities),
        ...extra,
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The localizations for whatever is on screen.
///
/// Read from a page's context, not from `MaterialApp`'s: `Localizations` is
/// installed *inside* `MaterialApp`, so asking the app for its own localizations
/// returns null — a null-check crash that looks like a missing translation.
AppLocalizations _l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first));

/// A stand-in for a picked photograph.
///
/// The file does not exist on disk, which is deliberate: the proof picker renders
/// through `Image.file` with an `errorBuilder`, so a test must not depend on a
/// real image being present to assert that the picker ran. The bytes are real
/// because the controller uploads the file, not the path — a test that stubbed
/// `readAsBytes` would not be testing the upload.
///
/// `path` rather than `name`: on IO, `XFile.fromData` documents `name` as
/// ignored, and [XFile.name] is derived from the path. A gallery file always has
/// a path, which is what the uploader's object-name convention reads.
XFile _proofFile() => XFile.fromData(
  Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0]),
  path: 'proof.jpg',
  mimeType: 'image/jpeg',
);

/// The `hintText` on each field of the create form.
///
/// Named rather than inlined for the reason the client flow tests give: a finder
/// built from a hint that has since been reworded fails at runtime, not at compile
/// time. Mirrors `app_en.arb`.
const String _makeHint = 'e.g. Toyota FJ';
const String _modelHint = 'e.g. FJ';
const String _yearHint = 'e.g. 2023';
const String _sellerNameHint = 'e.g. Abu Fahad';
const String _sellerPhoneHint = '05xxxxxxxx';

/// Fills the create form with the minimum that validates.
///
/// The notes box is left alone: it is the only optional field, and every test here
/// is about the centre card rather than about the rest of the form.
Future<void> _fillValidForm(WidgetTester tester) async {
  Future<void> enter(String hint, String value) =>
      tester.enterText(find.widgetWithText(TextFormField, hint), value);

  await enter(_makeHint, 'Toyota');
  await enter(_modelHint, 'FJ');
  await enter(_yearHint, '2023');
  await enter(_sellerPhoneHint, '0501234567');
  await _selectCity(tester, 'Dammam');
  await enter(_sellerNameHint, 'Abu Fahad');
  await tester.pumpAndSettle();
}

/// Chooses a city through the canonical-city picker.
///
/// Scrolls the field into view first: `tap` on an off-screen target silently does
/// nothing, and a form that has grown a card is exactly the case where the city
/// field can sit below the fold.
Future<void> _selectCity(WidgetTester tester, String city) async {
  await tester.ensureVisible(find.byType(CityPicker));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(CityPicker));
  await tester.pumpAndSettle();
  await tester.tap(find.text(city).last);
  await tester.pumpAndSettle();
}

/// The location round trip a buyer performs: open the sheet, drop the pin, confirm.
Future<void> _pickLocation(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  await tester.tap(find.text(l10n.customCentreLocationEmpty));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('stub-map')));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, l10n.createSubmit).last);
  await tester.pumpAndSettle();
}

/// The booking box's confirm button.
///
/// `textContaining` rather than `text`: the button's label is two lines joined by
/// a newline (`confirm` + `confirmNotify`), so its `Text.data` is the
/// concatenation and an exact match would never find it.
Finder _confirmButton(WidgetTester tester) =>
    find.textContaining(_l10nOf(tester).centreConfirm);

/// The booking box.
///
/// Everything in it is found relative to this, because the inspector shell is four
/// tabs and "the `SelectField`" is not a thing — several pages have one.
Finder _bookingBox(WidgetTester tester) => find.ancestor(
  of: _confirmButton(tester),
  matching: find.byType(NoticeBox),
);

/// The box's three fields in tree order.
///
/// Anchored on the box rather than on the page: `SelectField`'s `label` is a
/// semantics label rather than rendered text, so a text-based finder cannot tell
/// the centre from the day.
Finder _bookingFields(WidgetTester tester) => find.descendant(
  of: _bookingBox(tester),
  matching: find.byType(SelectField),
);

/// The box's centre field, which is the first of [\_bookingFields].
Finder _bookingCentreField(WidgetTester tester) =>
    _bookingFields(tester).first;

/// Picks today and the first offered time in the booking box's two-up fields.
Future<void> _pickDayAndTime(WidgetTester tester) async {
  final Finder fields = _bookingFields(tester);

  await tester.ensureVisible(fields.at(1));
  await tester.tap(fields.at(1));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();

  await tester.ensureVisible(fields.at(2));
  await tester.tap(fields.at(2));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}
