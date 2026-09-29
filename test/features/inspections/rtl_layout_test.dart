import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moaen/core/localization/locale_provider.dart';
import 'package:moaen/core/theme/app_theme.dart';
import 'package:moaen/features/auth/auth_controller.dart';
import 'package:moaen/features/auth/user_profile.dart';
import 'package:moaen/features/inspections/application/inspection_controller.dart';
import 'package:moaen/features/inspections/domain/inspection_request.dart';
import 'package:moaen/features/inspections/presentation/client_dashboard_page.dart';
import 'package:moaen/features/inspections/presentation/create_request_page.dart';
import 'package:moaen/features/inspections/presentation/my_requests_page.dart';
import 'package:moaen/features/inspections/presentation/request_detail_page.dart';
import 'package:moaen/l10n/gen/app_localizations.dart';
import 'package:moaen/features/cities/application/city_controller.dart';

import '../../support/fake_cities.dart';
import '../../support/fake_inspection_repository.dart';

/// Layout assertions for the Arabic, right-to-left presentation.
///
/// This file is separate from `client_request_flow_test.dart` on purpose. That
/// one renders in English and asserts behaviour; this one renders in Arabic and
/// asserts *geometry* — which edge something sits on, which way a row runs,
/// whether a string keeps its character order. Those are the assertions that pass
/// on a developer machine set to English and fail on an Arabic phone.
///
/// Geometry is read from laid-out rectangles rather than widget types, because a
/// widget tree can be structurally correct and still put a number on the wrong
/// side of the screen.
///
/// Expected strings come from [AppLocalizations] rather than being typed here.
/// A hard-coded Arabic literal would be a second copy of `app_ar.arb` that goes
/// stale silently, and diacritics in particular are easy to lose in transit —
/// "منتهٍ" without its tanween is a different string. Where the point of a test
/// is that the text is *Arabic*, that is asserted against the script rather than
/// against a specific phrase.
const UserProfile _buyer = UserProfile(
  id: 'user-1',
  fullName: 'Nadia Hassan',
  email: 'nadia@example.com',
  role: UserRole.client,
);

class _StubAuthController extends AuthController {
  @override
  Future<UserProfile?> build() async => _buyer;
}

/// Arabic script block, inclusive.
final RegExp _arabicScript = RegExp(r'[\u0600-\u06FF]');

/// A repo holding one open and one settled request, so a screen has both list
/// groups to lay out.
FakeInspectionRepository _withBothStates() => FakeInspectionRepository(
  requests: <InspectionRequest>[
    buildRequest(id: 'open-1', referenceNo: 9920, status: InspectionStatus.inProgress),
    buildRequest(id: 'done-1', referenceNo: 1002, status: InspectionStatus.completed),
  ],
);

Widget _arabic(FakeInspectionRepository repository, Widget child) =>
    ProviderScope(
      overrides: [
        inspectionRepositoryProvider.overrideWithValue(repository),
        authControllerProvider.overrideWith(_StubAuthController.new),
        localeProvider.overrideWithValue(const Locale('ar')),
        citiesProvider.overrideWith((Ref ref) async => testCities),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // No explicit `Directionality` wrapper. `MaterialApp` with an Arabic
        // locale is what supplies it, and a wrapper here would mask a screen
        // that broke the direction for itself.
        home: child,
      ),
    );

Widget _english(FakeInspectionRepository repository, Widget child) =>
    ProviderScope(
      overrides: [
        inspectionRepositoryProvider.overrideWithValue(repository),
        authControllerProvider.overrideWith(_StubAuthController.new),
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
    );

Future<void> _pump(
  WidgetTester tester,
  Widget app, {
  Size size = const Size(420, 1600),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

/// The localizations for whatever is on screen.
///
/// Read from a page's context, not from `MaterialApp`'s. `Localizations` is
/// installed *inside* `MaterialApp`, so asking the app for its own localizations
/// returns null — a null-check crash that looks like a missing translation.
AppLocalizations _l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first));

void main() {
  group('direction resolution', () {
    testWidgets('every client screen resolves to RTL in Arabic', (
      WidgetTester tester,
    ) async {
      for (final Widget page in <Widget>[
        const ClientDashboardPage(),
        const CreateRequestPage(),
        const MyRequestsPage(),
        const RequestDetailPage(id: 'req-1'),
      ]) {
        await _pump(tester, _arabic(_withBothStates(), page));

        // Read from the page's own context, so a wrapper forcing RTL would not
        // be able to mask a page that overrode the direction for itself.
        final BuildContext context = tester.element(find.byType(Scaffold).first);
        expect(
          Directionality.of(context),
          TextDirection.rtl,
          reason: '${page.runtimeType} did not resolve to RTL',
        );
      }
    });

    testWidgets('the same screens resolve to LTR in English', (
      WidgetTester tester,
    ) async {
      for (final Widget page in <Widget>[
        const ClientDashboardPage(),
        const CreateRequestPage(),
        const MyRequestsPage(),
        const RequestDetailPage(id: 'req-1'),
      ]) {
        await _pump(tester, _english(_withBothStates(), page));

        expect(
          Directionality.of(tester.element(find.byType(Scaffold).first)),
          TextDirection.ltr,
          reason: '${page.runtimeType} did not resolve to LTR',
        );
      }
    });
  });

  group('the reference number', () {
    testWidgets('leads the row on the right under RTL', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _arabic(_withBothStates(), const MyRequestsPage()));
      final AppLocalizations l10n = _l10nOf(tester);

      // In a `Row` under RTL the first child is laid out at the larger x. The
      // reference leads the row, so it must be right-most of the pair.
      final Rect reference = tester.getRect(find.text('MN-9920'));
      final Rect status = tester.getRect(find.text(l10n.statusInProgress));

      expect(
        reference.left,
        greaterThan(status.left),
        reason: 'the reference leads the row, so under RTL it must sit to the '
            'right of the status chip, not the left',
      );
    });

    testWidgets('leads the row on the left under LTR', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _english(_withBothStates(), const MyRequestsPage()));
      final AppLocalizations l10n = _l10nOf(tester);

      final Rect reference = tester.getRect(find.text('MN-9920'));
      final Rect status = tester.getRect(find.text(l10n.statusInProgress));

      expect(
        reference.left,
        lessThan(status.left),
        reason: 'the same row must reverse in English',
      );
    });

    testWidgets('keeps MN- before the digits inside an RTL paragraph', (
      WidgetTester tester,
    ) async {
      // The subtle one, and the reason [RenderParagraph] is reached for instead
      // of a `Text` finder. `Text.data` is the logical string the widget was
      // given; it says nothing about what was painted. Reading the laid-out
      // glyph boxes is the only way to tell "MN-9920" from "9920-MN".
      //
      // This is what makes the absence of a `TextDirection.ltr` override on the
      // reference deliberate rather than accidental. `MN-9920` is a single
      // left-to-right run, so bidi renders it correctly on its own; forcing LTR
      // would additionally flip `TextAlign.start` to *left* and put the number on
      // the wrong edge of an Arabic screen.
      await _pump(tester, _arabic(_withBothStates(), const MyRequestsPage()));

      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
        find.text('MN-9920'),
      );

      // "MN" occupies offsets 0..2; the digits 3..7.
      final List<TextBox> prefix = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 2),
      );
      final List<TextBox> digits = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 3, extentOffset: 7),
      );

      expect(prefix, isNotEmpty, reason: 'the prefix was not laid out at all');
      expect(digits, isNotEmpty, reason: 'the digits were not laid out at all');

      // `TextBox` offsets are in the paragraph's own space, which runs
      // right-to-left here, so "earlier in the run" is a *smaller* x.
      expect(
        prefix.first.left,
        lessThan(digits.first.left),
        reason: 'MN- must be painted to the LEFT of the digits; a larger x would '
            'mean the run was reversed by the direction override',
      );
    });
  });

  group('form geometry', () {
    testWidgets('text fields hug the right edge under RTL', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _arabic(FakeInspectionRepository(), const CreateRequestPage()));
      final AppLocalizations l10n = _l10nOf(tester);

      final Rect field = tester.getRect(
        find.widgetWithText(TextFormField, l10n.fieldCarMake),
      );
      final Rect page = tester.getRect(find.byType(Scaffold).first);

      // A left-aligned field in an Arabic form is the commonest RTL regression,
      // and it is invisible to a widget-tree assertion.
      expect(
        page.right - field.right,
        lessThan(page.width * 0.12),
        reason: 'the field should hug the right margin, not the left',
      );
    });

    testWidgets('text fields hug the left edge under LTR', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _english(FakeInspectionRepository(), const CreateRequestPage()));
      final AppLocalizations l10n = _l10nOf(tester);

      final Rect field = tester.getRect(
        find.widgetWithText(TextFormField, l10n.fieldCarMake),
      );
      final Rect page = tester.getRect(find.byType(Scaffold).first);

      expect(page.left - field.left, lessThan(page.width * 0.12));
    });

    testWidgets('the submit button spans the form width', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _arabic(FakeInspectionRepository(), const CreateRequestPage()));
      final AppLocalizations l10n = _l10nOf(tester);

      final Rect button = tester.getRect(
        find.widgetWithText(FilledButton, l10n.createSubmit),
      );
      final Rect page = tester.getRect(find.byType(Scaffold).first);

      // Full width, so it does not read as belonging to a left-hand column. The
      // fields moved inside section cards (which inset them further than the
      // page padding), so the button is compared against the page rather than a
      // field: what must hold is that the CTA spans the *form's* width.
      expect(page.right - button.right, lessThan(page.width * 0.12));
      expect(button.left - page.left, lessThan(page.width * 0.12));
      expect(button.width, greaterThan(page.width * 0.75));
    });
  });

  group('mirrored chrome', () {
    testWidgets('the details affordance moves to the left under RTL', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _arabic(_withBothStates(), const MyRequestsPage()));
      final AppLocalizations l10n = _l10nOf(tester);

      final Rect label = tester.getRect(find.text(l10n.actionViewDetails).first);
      final Rect chevron = tester.getRect(find.byIcon(Icons.chevron_right).first);

      // The glyph itself is pinned to LTR so it is not mirrored into a
      // meaningless shape; the *row* is what reverses. So under RTL the trailing
      // affordance belongs on the left, pointing the way the reader is going.
      expect(
        chevron.left,
        lessThan(label.left),
        reason: 'under RTL the trailing affordance belongs on the left',
      );
    });

    testWidgets('the details affordance moves to the right under LTR', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _english(_withBothStates(), const MyRequestsPage()));
      final AppLocalizations l10n = _l10nOf(tester);

      final Rect label = tester.getRect(find.text(l10n.actionViewDetails).first);
      final Rect chevron = tester.getRect(find.byIcon(Icons.chevron_right).first);

      expect(chevron.left, greaterThan(label.left));
    });
  });

  group('the content is Arabic, not English', () {
    testWidgets('the request list uses localized headings', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _arabic(_withBothStates(), const MyRequestsPage()));
      final AppLocalizations l10n = _l10nOf(tester);

      expect(find.text(l10n.myRequestsOpen), findsOneWidget);
      expect(find.text(l10n.myRequestsSettled), findsOneWidget);

      expect(
        _arabicScript.hasMatch(l10n.myRequestsOpen),
        isTrue,
        reason: 'the Arabic bundle must not be serving English',
      );
      // And the English wording is nowhere on an Arabic screen.
      expect(find.text('Open'), findsNothing);
      expect(find.text('Settled'), findsNothing);
    });

    testWidgets('the dashboard greets by name in Arabic', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _arabic(_withBothStates(), const ClientDashboardPage()));
      final AppLocalizations l10n = _l10nOf(tester);

      expect(find.text(l10n.dashboardGreeting(_buyer.fullName)), findsOneWidget);
      expect(find.text(l10n.dashboardActiveTitle), findsOneWidget);
      expect(find.textContaining('Hello'), findsNothing);
    });

    testWidgets('the create form is in Arabic', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _arabic(FakeInspectionRepository(), const CreateRequestPage()));
      final AppLocalizations l10n = _l10nOf(tester);

      expect(find.text(l10n.createSectionVehicle), findsOneWidget);
      expect(find.text(l10n.createSectionSeller), findsOneWidget);
      expect(_arabicScript.hasMatch(l10n.createSubmit), isTrue);
      expect(find.text('Send request'), findsNothing);
    });
  });
}
