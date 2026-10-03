import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:moaen/core/localization/locale_provider.dart';
import 'package:moaen/core/media/photo_picker.dart';
import 'package:moaen/core/theme/app_theme.dart';
import 'package:moaen/features/auth/auth_controller.dart';
import 'package:moaen/features/auth/auth_repository.dart';
import 'package:moaen/features/auth/presentation/access_restricted_page.dart';
import 'package:moaen/features/auth/sign_in_page.dart';
import 'package:moaen/features/auth/user_profile.dart';
import 'package:moaen/features/cities/application/city_controller.dart';
import 'package:moaen/l10n/gen/app_localizations.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_cities.dart';

/// The identity document, end to end: demanded at sign-up, and the one thing an
/// inspector with no other way forward can still go and supply.
///
/// Two halves that meet in one field. The registration form refuses to create an
/// account without a photograph — because an account with no document is one an
/// admin's queue cannot act on — and the restricted screen offers the upload again,
/// because migration 0011's grandfathering and a failed upload both produce exactly
/// that account, and the two places that can fix it are the two places under test
/// here.
///
/// The fake picker is the only way either control can be driven: a widget test cannot
/// open a device gallery, so a photo control that is not behind an interface is a
/// photo control with no tests.
class _FakePhotoPicker implements PhotoPicker {
  _FakePhotoPicker({this.file, this.throwInsteadOfReturning = false});

  /// What the "gallery" hands back. Null models the user dismissing it, which is a
  /// distinct outcome from a failure and must not be treated as one.
  XFile? file;

  /// Models a picker that throws rather than answering — which is what a platform
  /// channel does when the plugin is unregistered, and which the control has to
  /// survive without taking the screen with it.
  bool throwInsteadOfReturning;

  int calls = 0;

  @override
  Future<XFile?> pickFromGallery() async {
    calls++;
    if (throwInsteadOfReturning) throw StateError('no gallery');
    return file;
  }
}

/// A photograph, without touching the filesystem.
///
/// [XFile.fromData] ignores `name`, so the path is what the upload's extension check
/// would look at — set to something plausible rather than left empty.
final XFile _photo = XFile.fromData(
  Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0]),
  path: 'id-card.jpg',
);

UserProfile _inspector({
  bool approved = false,
  bool blocked = false,
  String? idPhotoPath,
  String? rejectionReason,
}) => UserProfile(
  id: 'user-1',
  fullName: 'Karim Adel',
  email: 'karim@example.com',
  role: UserRole.inspector,
  locationCity: 'Dammam',
  isApproved: approved,
  isBlocked: blocked,
  idPhotoPath: idPhotoPath,
  rejectionReason: rejectionReason,
);

/// Pumps [child] over a session described by [profile].
///
/// On a tall surface: the restricted screen is a `ListView` and the registration form
/// is a `Form` several screens long, so anything below the fold on the default
/// 800x600 viewport is absent from the tree rather than merely off screen.
Future<void> _pump(
  WidgetTester tester, {
  required UserProfile profile,
  required FakeAuthRepository repository,
  _FakePhotoPicker? picker,
  required Widget child,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1000, 3400);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        identityPhotoPickerProvider.overrideWithValue(
          picker ?? _FakePhotoPicker(file: _photo),
        ),
        localeProvider.overrideWithValue(const Locale('en')),
        citiesProvider.overrideWith((Ref ref) async => testCities),
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

void main() {
  group('the registration form', () {
    testWidgets('will not create an account without a document', (
      WidgetTester tester,
    ) async {
      // The requirement is the whole point of the field, and an account with no
      // document is one an admin's queue cannot review. So the refusal is *before*
      // the tap — a greyed button — rather than a failure after it: the alternative
      // is an account that exists and cannot be verified.
      await _pump(
        tester,
        profile: _inspector(),
        repository: FakeAuthRepository(profile: _inspector()),
        child: const SignInPage(),
      );

      await tester.tap(find.text('New to Moaen? Create an account'));
      await tester.pumpAndSettle();

      expect(find.text('Add your ID'), findsOneWidget);
      final Finder submit = find.widgetWithText(FilledButton, 'Create account');
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      // And a filled form changes nothing on its own: the document is not a field.
      await tester.enterText(find.byType(TextFormField).at(0), 'Karim Adel');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'karim@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(2), 'Passw0rd!');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    });

    testWidgets('asks for the document from a buyer as well as an inspector', (
      WidgetTester tester,
    ) async {
      // A buyer uses the platform the moment they sign up, so an unverified buyer is
      // working and an inspector is not — but the document is wanted from both. A
      // control that appeared for only one role would make it look optional to the
      // other, and the "no document" queue row would come from half the signups.
      await _pump(
        tester,
        profile: _inspector(),
        repository: FakeAuthRepository(profile: _inspector()),
        child: const SignInPage(),
      );

      await tester.tap(find.text('New to Moaen? Create an account'));
      await tester.pumpAndSettle();

      // The buyer is the default segment, and the document field is there for them.
      expect(find.text('Add your ID'), findsOneWidget);
      // The city picker is the inspector-only field, and it is absent — so the two
      // role differences are genuinely independent controls.
      expect(find.text('Service city'), findsNothing);
    });

    testWidgets('a chosen document confirms itself and unlocks the button', (
      WidgetTester tester,
    ) async {
      final _FakePhotoPicker picker = _FakePhotoPicker(file: _photo);

      await _pump(
        tester,
        profile: _inspector(),
        repository: FakeAuthRepository(profile: _inspector()),
        picker: picker,
        child: const SignInPage(),
      );

      await tester.tap(find.text('New to Moaen? Create an account'));
      await tester.pumpAndSettle();

      expect(find.text('ID photo on file'), findsNothing);
      await tester.tap(find.text('Upload ID photo'));
      await tester.pumpAndSettle();

      expect(picker.calls, 1);
      // One confirmed line under the control, rather than a relabelled button: the
      // button saying "replace" would read as a different action, and the file name
      // would read as `IMG_0042.jpg` with no indication of what it is.
      expect(find.text('ID photo on file'), findsOneWidget);
      // The button keeps its label, so the only thing that changed is the state.
      expect(find.text('Upload ID photo'), findsOneWidget);
    });

    testWidgets('dismissing the gallery is not a failure', (
      WidgetTester tester,
    ) async {
      // The picker answers null when the user backs out. Treating that as a failed
      // upload would relabel the button "Try again" for someone who simply changed
      // their mind, and would be the more alarming of the two readings.
      await _pump(
        tester,
        profile: _inspector(),
        repository: FakeAuthRepository(profile: _inspector()),
        picker: _FakePhotoPicker(file: null),
        child: const SignInPage(),
      );

      await tester.tap(find.text('New to Moaen? Create an account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload ID photo'));
      await tester.pumpAndSettle();

      expect(find.text('ID photo on file'), findsNothing);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Upload ID photo'), findsOneWidget);
    });
  });

  group('the restricted screen', () {
    testWidgets('offers the upload to an inspector with no document', (
      WidgetTester tester,
    ) async {
      // The grandfathering case: an inspector who predates the requirement, or whose
      // sign-up upload failed. They are blocked on the paperwork, and replacing it is
      // the only action that could change their state — so the control is on screen.
      await _pump(
        tester,
        profile: _inspector(),
        repository: FakeAuthRepository(profile: _inspector()),
        child: const AccessRestrictedPage(),
      );

      expect(find.text('Awaiting verification'), findsOneWidget);
      expect(find.text('Add your ID'), findsOneWidget);
      expect(find.text('Upload ID photo'), findsOneWidget);
    });

    testWidgets('a successful upload takes the control away', (
      WidgetTester tester,
    ) async {
      // The screen decides whether to offer the upload from `id_photo_path`, so a
      // successful write has to move the *profile* for the control to disappear — not
      // merely hide itself. This is what proves the retry is wired to the real
      // repository rather than to local state.
      final FakeAuthRepository repository = FakeAuthRepository(
        profile: _inspector(),
      )..profileAfterIdPhoto = _inspector(idPhotoPath: 'user-1/id.jpg');

      await _pump(
        tester,
        profile: _inspector(),
        repository: repository,
        child: const AccessRestrictedPage(),
      );

      await tester.tap(find.text('Upload ID photo'));
      await tester.pumpAndSettle();

      expect(repository.idPhotoUploads, 1);
      // The document is on file now, so the control — and the notice around it —
      // have nothing left to do. What remains is the approval wait, which is the
      // platform's to resolve and not the inspector's.
      expect(find.text('Upload ID photo'), findsNothing);
      expect(find.text('Add your ID'), findsNothing);
      expect(find.text('Awaiting verification'), findsOneWidget);
    });

    testWidgets('a failed upload says so by relabelling the button', (
      WidgetTester tester,
    ) async {
      // A retry is a second explicit press of a button the user is looking at. If a
      // failure left the screen exactly as it was, the button would be
      // indistinguishable from one that does nothing, and the inspector would have no
      // way to tell a failed write from a broken app.
      final FakeAuthRepository repository =
          FakeAuthRepository(profile: _inspector())
            ..idPhotoFailure = const AuthFailure(
              AuthFailureReason.profileUnavailable,
            );

      await _pump(
        tester,
        profile: _inspector(),
        repository: repository,
        child: const AccessRestrictedPage(),
      );

      await tester.tap(find.text('Upload ID photo'));
      await tester.pumpAndSettle();

      expect(repository.idPhotoUploads, 1);
      // A message rather than a banner: the paragraph above the control already
      // explains that the document is missing, and a "that failed" box under a
      // control that changed its own label would state the same thing twice.
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Upload ID photo'), findsNothing);
      // And the session survived it. Losing the account over a storage outage is the
      // worst possible answer to the least likely failure.
      expect(find.text('Awaiting verification'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('the retry button works as the label promises', (
      WidgetTester tester,
    ) async {
      // "Try again" has to *try again*. A relabel with no second attempt behind it
      // would be a lie told by the one control that has just failed.
      final FakeAuthRepository repository =
          FakeAuthRepository(profile: _inspector())
            ..idPhotoFailure = const AuthFailure(
              AuthFailureReason.profileUnavailable,
            );

      await _pump(
        tester,
        profile: _inspector(),
        repository: repository,
        child: const AccessRestrictedPage(),
      );

      await tester.tap(find.text('Upload ID photo'));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);

      // Storage recovers.
      repository.idPhotoFailure = null;
      repository.profileAfterIdPhoto = _inspector(idPhotoPath: 'user-1/id.jpg');
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(repository.idPhotoUploads, 2);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Upload ID photo'), findsNothing);
    });

    testWidgets('a picker that throws does not take the screen with it', (
      WidgetTester tester,
    ) async {
      // A platform channel that throws is a plugin problem, not an account problem.
      // Letting it escape would tear down the only screen an unapproved inspector can
      // reach, which is the screen they would then need in order to recover.
      await _pump(
        tester,
        profile: _inspector(),
        repository: FakeAuthRepository(profile: _inspector()),
        picker: _FakePhotoPicker(throwInsteadOfReturning: true),
        child: const AccessRestrictedPage(),
      );

      await tester.tap(find.text('Upload ID photo'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Awaiting verification'), findsOneWidget);
    });

    testWidgets('does not offer the upload to a suspended account', (
      WidgetTester tester,
    ) async {
      // The blocker for a suspension is the account, not the paperwork, so an upload
      // control there is an invitation to keep trying — and a second thing to fail
      // while the real blocker goes unaddressed.
      await _pump(
        tester,
        profile: _inspector(blocked: true),
        repository: FakeAuthRepository(profile: _inspector(blocked: true)),
        child: const AccessRestrictedPage(),
      );

      expect(find.text('Account suspended'), findsOneWidget);
      expect(find.text('Add your ID'), findsNothing);
      expect(find.text('Upload ID photo'), findsNothing);
    });

    testWidgets(
      'tells a rejected inspector the reason, and still takes a document',
      (WidgetTester tester) async {
        // The reason is an admin's free text, so it may be anything — including
        // nothing, which is why the title is the fallback rather than the other way
        // round. And a refusal is about the *account*, but replacing the document is
        // still the only thing the inspector can act on, so the control stays.
        await _pump(
          tester,
          profile: _inspector(rejectionReason: 'The ID photo was unreadable.'),
          repository: FakeAuthRepository(
            profile: _inspector(
              rejectionReason: 'The ID photo was unreadable.',
            ),
          ),
          child: const AccessRestrictedPage(),
        );

        expect(find.text('Account not approved'), findsOneWidget);
        expect(
          find.text(
            'Your account was not approved: The ID photo was unreadable.',
          ),
          findsOneWidget,
        );
        expect(find.text('Upload ID photo'), findsOneWidget);
      },
    );

    testWidgets('an inspector who is simply waiting is not nagged', (
      WidgetTester tester,
    ) async {
      // Waiting for a decision with the document already on file is the ordinary
      // state. Showing the upload control would imply something is missing.
      await _pump(
        tester,
        profile: _inspector(idPhotoPath: 'user-1/id.jpg'),
        repository: FakeAuthRepository(
          profile: _inspector(idPhotoPath: 'user-1/id.jpg'),
        ),
        child: const AccessRestrictedPage(),
      );

      expect(find.text('Awaiting verification'), findsOneWidget);
      expect(find.text('Add your ID'), findsNothing);
      expect(find.text('Upload ID photo'), findsNothing);
    });

    testWidgets('signing out from the restricted screen works', (
      WidgetTester tester,
    ) async {
      // The one control that has to be on all four states: it is how somebody whose
      // account is wrong gets out of it.
      final FakeAuthRepository repository = FakeAuthRepository(
        profile: _inspector(),
      );

      await _pump(
        tester,
        profile: _inspector(),
        repository: repository,
        child: const AccessRestrictedPage(),
      );

      await tester.tap(find.text('Sign out'));
      await tester.pump();

      // The fake leaves the session standing, because a widget test cannot observe
      // the router's response to a null profile — the write is the thing here. With
      // no profile the page falls back to its loading state, which the router
      // resolves by sending the account to the sign-in screen.
      expect(repository.signOutCalls, 1);
      expect(find.text('Awaiting verification'), findsNothing);
    });
  });
}
