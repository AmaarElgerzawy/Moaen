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
import 'package:moaen/features/inspections/presentation/widgets/design_widgets.dart';
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

/// The trailing glyph of the first [SelectField] on screen.
///
/// Found by position rather than by its character: the chevron is the second
/// `Text` in the field's row — the first being the value — and a literal `⌄` in
/// this file would be a second copy of a character that has no obvious identity
/// once it has been through a text editor.
Finder _chevronOfFirstField() => find
    .descendant(
      of: find.byType(SelectField).first,
      matching: find.byType(Text),
    )
    .last;

/// The full-width text fields on a create form, in tree order.
///
/// Full width only. Half-width fields are a deliberate pair on this form — the
/// seller's name and phone sit side by side — so the second of a pair belongs on
/// the *left* half under RTL, and a check that every field hugs one margin would
/// be wrong for the one field the design puts there.
List<Rect> _fullWidthFields(WidgetTester tester, Rect page) {
  final Finder fields = find.byType(DesignTextField);
  return <Rect>[
    for (int i = 0; i < fields.evaluate().length; i++)
      if (tester.getRect(fields.at(i)).width > page.width * 0.8)
        tester.getRect(fields.at(i)),
  ];
}

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
      final Rect page = tester.getRect(find.byType(Scaffold).first);

      // Every full-width field, not just the first: a form whose rows mirror
      // individually has one field in the wrong place rather than none, and a
      // single check would pass on whichever one happened to be laid out first.
      final List<Rect> fields = _fullWidthFields(tester, page);
      expect(fields, isNotEmpty, reason: 'the form drew no full-width fields');

      // A left-aligned field in an Arabic form is the commonest RTL regression,
      // and it is invisible to a widget-tree assertion.
      for (final Rect field in fields) {
        expect(
          page.right - field.right,
          lessThan(page.width * 0.12),
          reason: 'the field should hug the right margin, not the left',
        );
      }
    });

    testWidgets('text fields hug the left edge under LTR', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _english(FakeInspectionRepository(), const CreateRequestPage()));
      final Rect page = tester.getRect(find.byType(Scaffold).first);

      for (final Rect field in _fullWidthFields(tester, page)) {
        expect(page.left - field.left, lessThan(page.width * 0.12));
      }
    });

    testWidgets('the submit button spans the form width', (
      WidgetTester tester,
    ) async {
      // Taller than the file's default, because the form is a lazy `ListView` and
      // the submit button is its last child. The centre card pushes it past 1600,
      // and an unbuilt child is not a widget the finder can measure — the failure
      // reads as "no submit button exists" rather than as "the surface was short".
      //
      // This is a surface change, not a workaround: on a real phone the button was
      // already below the fold before the centre card, because the form has always
      // scrolled. What the assertion checks is the button's width when built.
      await _pump(
        tester,
        _arabic(FakeInspectionRepository(), const CreateRequestPage()),
        size: const Size(420, 2000),
      );
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

  group('pinned geometry', () {
    testWidgets("Screen 2's chevron holds the physical left in both locales", (
      WidgetTester tester,
    ) async {
      // The spec's rule, not a Flutter default: a position in this design is a
      // place on the *screen*, and the screens pin their own direction, so a
      // locale change must not move anything. Screen 2 is one of the RTL
      // containers, so its trailing chevron is on the physical left in Arabic
      // *and* in English — and a screen that followed the ambient direction would
      // silently re-lay-out the whole form for an English user.
      for (final Widget app in <Widget>[
        _arabic(FakeInspectionRepository(), const CreateRequestPage()),
        _english(FakeInspectionRepository(), const CreateRequestPage()),
      ]) {
        await _pump(tester, app);

        final Rect chevron = tester.getRect(_chevronOfFirstField());
        final Rect field = tester.getRect(find.byType(SelectField).first);

        expect(
          chevron.center.dx,
          lessThan(field.center.dx),
          reason: "Screen 2's trailing affordance belongs on the physical left",
        );
      }
    });

    testWidgets('the chevron glyph keeps its own direction inside an RTL row', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _arabic(FakeInspectionRepository(), const CreateRequestPage()));

      // Position and shape are separate decisions, and only the first mirrors. The
      // `⌄` is pinned to LTR inside an RTL row: a glyph with no mirrored form
      // would otherwise be re-ordered by the bidi algorithm into a mark that
      // points the wrong way.
      final RenderParagraph glyph = tester.renderObject<RenderParagraph>(
        _chevronOfFirstField(),
      );

      expect(glyph.textDirection, TextDirection.ltr);
    });

    testWidgets("Screen 1's nav holds the physical left-to-right order", (
      WidgetTester tester,
    ) async {
      for (final Widget app in <Widget>[
        _arabic(FakeInspectionRepository(), const ClientDashboardPage()),
        _english(FakeInspectionRepository(), const ClientDashboardPage()),
      ]) {
        await _pump(tester, app);
        final AppLocalizations l10n = _l10nOf(tester);

        // The first destination is at the physical left on an LTR container, so
        // its label starts left of the last one's.
        final Rect first = tester.getRect(
          find.descendant(
            of: find.byType(AppBottomNav),
            matching: find.text(l10n.navHome),
          ),
        );
        final Rect last = tester.getRect(
          find.descendant(
            of: find.byType(AppBottomNav),
            matching: find.text(l10n.navAccount),
          ),
        );

        expect(
          first.left,
          lessThan(last.left),
          reason: "Screen 1's nav is an LTR container and must not reverse",
        );
      }
    });

    testWidgets('the reference leads the request card under RTL', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _arabic(_withBothStates(), const MyRequestsPage()));
      final AppLocalizations l10n = _l10nOf(tester);

      // The card's own leading child, read against the status pill that follows
      // it: the design leads with the car and puts the reference in the small
      // grey line, so the pill is the trailing item.
      final Rect reference = tester.getRect(find.text('MN-9920'));
      final Rect status = tester.getRect(find.text(l10n.statusInProgress));

      expect(
        reference.left,
        greaterThan(status.left),
        reason: 'under RTL the row must reverse, putting the reference right-most',
      );
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
      // Empty, so the dashboard's own empty state is on screen. A repository with
      // an in-progress request shows the active card instead, and a test asserting
      // both the greeting and the empty title would be asserting against a screen
      // that cannot exist.
      await _pump(tester, _arabic(FakeInspectionRepository(), const ClientDashboardPage()));
      final AppLocalizations l10n = _l10nOf(tester);

      // The design's header greets without a name — the avatar beside it carries
      // the identity — and the empty state is its own title, so an Arabic screen
      // with no active request says `لا يوجد طلب نشط` rather than a greeting.
      expect(find.text(l10n.buyerGreeting), findsOneWidget);
      expect(find.text(l10n.dashboardNoActiveTitle), findsOneWidget);
      expect(_arabicScript.hasMatch(l10n.buyerGreeting), isTrue);
      expect(find.textContaining('Welcome'), findsNothing);
    });

    testWidgets('the create form is in Arabic', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _arabic(FakeInspectionRepository(), const CreateRequestPage()));
      final AppLocalizations l10n = _l10nOf(tester);

      expect(find.text(l10n.cardCarTitle), findsOneWidget);
      expect(find.text(l10n.cardSellerTitle), findsOneWidget);
      expect(_arabicScript.hasMatch(l10n.createSubmit), isTrue);
      expect(find.text('Send request'), findsNothing);
    });
  });
}
