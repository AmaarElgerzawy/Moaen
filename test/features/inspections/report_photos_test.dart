import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:moaen/core/localization/locale_provider.dart';
import 'package:moaen/core/theme/app_theme.dart';
import 'package:moaen/features/auth/auth_controller.dart';
import 'package:moaen/features/auth/user_profile.dart';
import 'package:moaen/features/inspections/application/inspection_controller.dart';
import 'package:moaen/features/inspections/data/media_repository.dart';
import 'package:moaen/features/inspections/domain/report_media.dart';
import 'package:moaen/features/inspections/presentation/report_entry_page.dart';
import 'package:moaen/features/inspections/presentation/widgets/design_widgets.dart';
import 'package:moaen/l10n/gen/app_localizations.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_inspection_repository.dart';
import '../../support/fake_media_repository.dart';

/// Screen 5's photo card, and the issue write behind it.
///
/// The reference draws four squares — three filled, one dashed — which reads as a
/// finished screenshot rather than an initial state. These tests pin what the card
/// does instead: the filled tiles are the report's actual `report_media` rows, the
/// dashed tile is the only control, and the bytes go to `inspection-media` before
/// the report is certified rather than after.

/// One stored photo, for the grid tests.
ReportMedia _photo(int index) => ReportMedia(
  id: 'media-$index',
  reportId: FakeReportRepository.reportId,
  path: 'job-1/$index.jpg',
  url: 'https://test.supabase.co/signed/$index.jpg',
);

/// A picker answer that names a real file on disk, because [PhotoSlot] renders the
/// unsaved ones with `Image.file` and a missing path is an exception, not a blank.
XFile _picked(String name) {
  final File file = File('${Directory.systemTemp.path}/$name')
    ..writeAsBytesSync(<int>[0, 1, 2, 3]);
  return XFile(file.path, name: name);
}

Widget _app({
  required FakeReportRepository reports,
  required FakeMediaRepository media,
  required FakePhotoPicker picker,
  Locale locale = const Locale('en'),
}) => ProviderScope(
  overrides: [
    reportRepositoryProvider.overrideWithValue(reports),
    mediaRepositoryProvider.overrideWithValue(media),
    photoPickerProvider.overrideWithValue(picker),
    inspectionRepositoryProvider.overrideWithValue(FakeInspectionRepository()),
    authControllerProvider.overrideWith(_StubAuthController.new),
    authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
    localeProvider.overrideWithValue(locale),
  ],
  child: MaterialApp(
    locale: locale,
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const ReportEntryPage(id: 'job-1'),
  ),
);

/// The inspector these tests are signed in as.
///
/// The report's own screen reads no profile, but `reportMediaProvider` watches the
/// auth controller so a sign-out cannot leave the previous inspector's photos on
/// screen, so there has to be a controller to watch.
class _StubAuthController extends AuthController {
  @override
  Future<UserProfile?> build() async => const UserProfile(
    id: 'inspector-1',
    fullName: 'Karim Adel',
    email: 'karim@example.com',
    role: UserRole.inspector,
    locationCity: 'Dammam',
    rating: 4.5,
  );
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ReportEntryPage)));

/// Settles the form and returns the localizations, once the cards are on screen.
///
/// The surface is a phone's width and a very tall viewport on purpose. Screen 5 is
/// one long `ListView`, and a `ListView` builds only what is near the viewport — so
/// at the default 800x600 test surface the photo card, the attestation and the
/// issue button do not exist as far as the finder is concerned, and every
/// assertion about them would be about nothing.
Future<AppLocalizations> _open(
  WidgetTester tester, {
  required FakeReportRepository reports,
  required FakeMediaRepository media,
  required FakePhotoPicker picker,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 2800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    _app(reports: reports, media: media, picker: picker),
  );
  await tester.pumpAndSettle();
  return _l10n(tester);
}

void main() {
  // The path convention, which the storage policy in migration 0003 parses.
  group('MediaRepository object naming', () {
    final DateTime at = DateTime.utc(2026, 3, 4, 5, 6, 7, 8);

    test('keeps a known image extension', () {
      expect(
        MediaRepository.objectNameFor('image_picker99.png', at: at),
        endsWith('.png'),
      );
    });

    test('falls back to .jpg for a name with no usable extension', () {
      // The picker's own naming carries one, but a file from a provider or an
      // older upload does not, and storing it as a name with no extension means
      // Storage serves it as octet-stream.
      expect(
        MediaRepository.objectNameFor('IMG_0001', at: at),
        endsWith('.jpg'),
      );
    });

    test('never carries the source app name through', () {
      final String name = MediaRepository.objectNameFor(
        'image_picker1745000000000.jpeg',
        at: at,
      );
      expect(name, isNot(contains('image_picker')));
    });

    test('names by the clock, so two photos a millisecond apart do not collide', () {
      final String first = MediaRepository.objectNameFor('a.jpg', at: at);
      final String second = MediaRepository.objectNameFor(
        'a.jpg',
        at: at.add(const Duration(milliseconds: 1)),
      );
      // Same second, same extension, same source name — the clock is the only
      // thing that tells them apart, which is the whole reason it is in there.
      expect(first, isNot(second));
      expect(first.endsWith('.jpg'), isTrue);
      expect(second.endsWith('.jpg'), isTrue);
    });

    test('has no separator in it, because the policy reads the path segments', () {
      // `storage_inspection_id` takes the first segment as the inspection id; a
      // separator inside the file name would be harmless here but the name must
      // never be able to become the head of the path.
      expect(
        MediaRepository.objectNameFor('../../etc/passwd', at: at),
        isNot(contains('/')),
      );
    });

    test('records the content type the object is served with', () {
      expect(MediaRepository.contentTypeFor('job-1/a.png'), 'image/png');
      expect(MediaRepository.contentTypeFor('job-1/a.webp'), 'image/webp');
      expect(MediaRepository.contentTypeFor('job-1/a.heic'), 'image/heic');
      expect(MediaRepository.contentTypeFor('job-1/a.jpg'), 'image/jpeg');
      // The fallback has to be an image type, not the default binary type the
      // upload would otherwise infer from an unknown extension.
      expect(MediaRepository.contentTypeFor('job-1/a'), 'image/jpeg');
    });
  });

  group('Screen 5 photo card', () {
    testWidgets('with no photos the only tile is the dashed add', (
      WidgetTester tester,
    ) async {
      final AppLocalizations l10n = await _open(
        tester,
        reports: FakeReportRepository(bundle: testReportBundle()),
        media: FakeMediaRepository(),
        picker: FakePhotoPicker(),
      );

      expect(find.byType(PhotoSlot), findsOneWidget);
      expect(find.text(l10n.reportPhotoAdd), findsOneWidget);
    });

    testWidgets('a stored photo renders its signed URL', (
      WidgetTester tester,
    ) async {
      await _open(
        tester,
        reports: FakeReportRepository(bundle: testReportBundle()),
        media: FakeMediaRepository(media: <ReportMedia>[_photo(1)]),
        picker: FakePhotoPicker(),
      );

      // The tile has become an image: the caption is gone, because a caption on
      // top of the picture it names is redundant.
      expect(find.byType(Image), findsOneWidget);
      final Image image = tester.widget(find.byType(Image));
      expect(image.image, isA<NetworkImage>());
    });

    testWidgets('the four tiles fill two columns, the first on the physical right', (
      WidgetTester tester,
    ) async {
      await _open(
        tester,
        reports: FakeReportRepository(bundle: testReportBundle()),
        media: FakeMediaRepository(
          media: <ReportMedia>[_photo(1), _photo(2), _photo(3)],
        ),
        picker: FakePhotoPicker(),
      );

      expect(find.byType(PhotoSlot), findsNWidgets(4));

      // Physical positions, because the design fixes them. Two facts have to hold
      // together here, and both are pinned:
      //
      //  * `find.byType` returns *tree* order, and the tree is column-major —
      //    photo 1, photo 3, then photo 2 and the add tile. Reading it as
      //    left-to-right would put the wrong pair in the same column.
      //  * Screen 5 is an RTL container, so a `Row`'s first child is at the
      //    physical *right*. The design's first column is the right-hand one.
      final List<Offset> tiles = tester
          .widgetList<PhotoSlot>(find.byType(PhotoSlot))
          .map((PhotoSlot slot) => tester.getTopLeft(find.byWidget(slot)))
          .toList();

      // Photos 1 and 3 share a column; photos 2 and the add tile share the other.
      expect(tiles[0].dx, tiles[1].dx);
      expect(tiles[2].dx, tiles[3].dx);
      expect(tiles[0].dx, isNot(tiles[2].dx));

      // The first column is the physical right.
      expect(tiles[0].dx, greaterThan(tiles[2].dx));

      // Each column stacks downward, so the second tile is below the first.
      expect(tiles[1].dy, greaterThan(tiles[0].dy));
      expect(tiles[3].dy, greaterThan(tiles[2].dy));
      // And the two columns' top rows line up.
      expect(tiles[0].dy, tiles[2].dy);
    });

    testWidgets('the add tile is the last one in reading order', (
      WidgetTester tester,
    ) async {
      final AppLocalizations l10n = await _open(
        tester,
        reports: FakeReportRepository(bundle: testReportBundle()),
        media: FakeMediaRepository(
          media: <ReportMedia>[_photo(1), _photo(2), _photo(3)],
        ),
        picker: FakePhotoPicker(),
      );

      final List<PhotoSlot> tiles = tester
          .widgetList<PhotoSlot>(find.byType(PhotoSlot))
          .toList();
      expect(tiles.last.label, l10n.reportPhotoAdd);
      // And it is the only tappable one: an evidence photo cannot be removed,
      // because `report_media` grants insert and select and nothing else.
      expect(tiles.last.onTap, isNotNull);
      for (final PhotoSlot slot in tiles.take(3)) {
        expect(slot.onTap, isNull);
      }
    });

    testWidgets('tapping add opens the gallery and the photo appears', (
      WidgetTester tester,
    ) async {
      final FakePhotoPicker picker = FakePhotoPicker(
        answers: <XFile?>[_picked('corners.png')],
      );
      await _open(
        tester,
        reports: FakeReportRepository(bundle: testReportBundle()),
        media: FakeMediaRepository(),
        picker: picker,
      );

      await tester.tap(find.text(_l10n(tester).reportPhotoAdd));
      await tester.pumpAndSettle();

      expect(picker.calls, 1);
      expect(find.byType(PhotoSlot), findsNWidgets(2));
      // Rendered from the device, not the network: it has not been uploaded yet.
      final List<Image> images = tester
          .widgetList<Image>(find.byType(Image))
          .toList();
      expect(images.single.image, isA<FileImage>());
    });

    testWidgets('dismissing the gallery changes nothing', (
      WidgetTester tester,
    ) async {
      final FakePhotoPicker picker = FakePhotoPicker(
        answers: <XFile?>[null],
      );
      await _open(
        tester,
        reports: FakeReportRepository(bundle: testReportBundle()),
        media: FakeMediaRepository(),
        picker: picker,
      );

      await tester.tap(find.text(_l10n(tester).reportPhotoAdd));
      await tester.pumpAndSettle();

      expect(picker.calls, 1);
      expect(find.byType(PhotoSlot), findsOneWidget);
    });

    testWidgets('photos already on the report lead the ones just picked', (
      WidgetTester tester,
    ) async {
      final FakePhotoPicker picker = FakePhotoPicker(
        answers: <XFile?>[_picked('new.png')],
      );
      await _open(
        tester,
        reports: FakeReportRepository(bundle: testReportBundle()),
        media: FakeMediaRepository(media: <ReportMedia>[_photo(1)]),
        picker: picker,
      );

      await tester.tap(find.text(_l10n(tester).reportPhotoAdd));
      await tester.pumpAndSettle();

      final List<Image> images = tester
          .widgetList<Image>(find.byType(Image))
          .toList();
      expect(images.length, 2);
      // Reading order is what the reopened form is showing: the record first.
      expect(images.first.image, isA<NetworkImage>());
      expect(images.last.image, isA<FileImage>());
    });
  });

  group('issuing a report with photos', () {
    /// Fills the two required verdicts and taps the issue button.
    ///
    /// Both verdicts are required by `_issue`, so a test that wants to reach the
    /// write has to answer them the way an inspector would. Tapping the option's own
    /// label rather than the centre of the whole control: the segments sit in a row
    /// with padding around them, and a tap at the geometric centre of the control
    /// can land in the gap between two segments.
    ///
    /// The body's two `ChoiceField`s are the same control as its `SegmentedChoice`
    /// — they share one selection — so one tap answers all three.
    Future<void> submit(WidgetTester tester, AppLocalizations l10n) async {
      await tester.tap(find.text(l10n.reportObdClean));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.reportBodySound));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.reportIssueButton));
      await tester.pumpAndSettle();
    }

    testWidgets('photos upload before the report is certified', (
      WidgetTester tester,
    ) async {
      final FakeReportRepository reports = FakeReportRepository(
        bundle: testReportBundle(),
      );
      final FakeMediaRepository media = FakeMediaRepository();
      final FakePhotoPicker picker = FakePhotoPicker(
        answers: <XFile?>[_picked('odometer.png')],
      );
      final AppLocalizations l10n = await _open(
        tester,
        reports: reports,
        media: media,
        picker: picker,
      );

      await tester.tap(find.text(l10n.reportPhotoAdd));
      await tester.pumpAndSettle();
      await submit(tester, l10n);

      // The order is the whole point: a report that certifies with its photos
      // still in flight is a document that says there are none.
      expect(
        reports.writes,
        <String>['upsert', 'sections', 'parts', 'certify'],
      );
      expect(media.attachedFor, <String>['job-1/${FakeReportRepository.reportId}']);
      expect(media.attachedNames.single.single, endsWith('odometer.png'));
    });

    testWidgets('a report with no photos skips the upload entirely', (
      WidgetTester tester,
    ) async {
      final FakeReportRepository reports = FakeReportRepository(
        bundle: testReportBundle(),
      );
      final FakeMediaRepository media = FakeMediaRepository();
      final AppLocalizations l10n = await _open(
        tester,
        reports: reports,
        media: media,
        picker: FakePhotoPicker(),
      );

      await submit(tester, l10n);

      expect(media.attachedNames, isEmpty);
      expect(reports.writes.last, 'certify');
    });

    testWidgets('a failed upload leaves the report uncertified', (
      WidgetTester tester,
    ) async {
      final FakeReportRepository reports = FakeReportRepository(
        bundle: testReportBundle(),
      );
      final FakeMediaRepository media = FakeMediaRepository();
      final FakePhotoPicker picker = FakePhotoPicker(
        answers: <XFile?>[_picked('engine.png')],
      );
      final AppLocalizations l10n = await _open(
        tester,
        reports: reports,
        media: media,
        picker: picker,
      );

      await tester.tap(find.text(l10n.reportPhotoAdd));
      await tester.pumpAndSettle();

      media.attachFailure = StateError('no signal');
      await submit(tester, l10n);

      // The inspector's findings were saved, but the document is not published:
      // a certified report missing the photos the inspector just attached is
      // worse than an uncertified draft they can retry.
      expect(reports.writes, <String>['upsert', 'sections', 'parts']);
      expect(reports.writes, isNot(contains('certify')));
      expect(find.text(l10n.reportIssueButton), findsOneWidget);
    });
  });

  test('the storage bucket is the one migration 0003 created', () {
    // A one-line guard on the single constant everything else derives from: the
    // object path is only readable because the policy names this bucket, and a
    // rename here would fail every upload as a bare 400.
    expect(MediaRepository.bucket, 'inspection-media');
  });
}