import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moaen/core/localization/locale_provider.dart';
import 'package:moaen/core/theme/app_theme.dart';
import 'package:moaen/features/auth/auth_controller.dart';
import 'package:moaen/features/auth/user_profile.dart';
import 'package:moaen/features/inspections/application/inspection_controller.dart';
// Not transitive from the fake: Dart imports are per-library, so a test that
// constructs an `InspectionFailure` has to name where it comes from.
import 'package:moaen/features/inspections/data/inspection_repository.dart';
import 'package:moaen/features/inspections/domain/inspection_draft.dart';
import 'package:moaen/features/inspections/domain/inspection_request.dart';
import 'package:moaen/features/inspections/presentation/client_dashboard_page.dart';
import 'package:moaen/features/inspections/presentation/create_request_page.dart';
import 'package:moaen/features/inspections/presentation/my_requests_page.dart';
import 'package:moaen/features/inspections/presentation/request_detail_page.dart';
import 'package:moaen/features/inspections/presentation/widgets/design_widgets.dart';
import 'package:moaen/l10n/gen/app_localizations.dart';
import 'package:moaen/features/cities/application/city_controller.dart';
import 'package:moaen/features/cities/presentation/city_picker.dart';

import '../../support/fake_cities.dart';
import '../../support/fake_inspection_repository.dart';

/// Widget tests for the three client screens.
///
/// Rendered in English deliberately: these tests are about behaviour — which
/// screen, which row, which action — and asserting on Arabic strings would make
/// a translation change look like a functional break. The Arabic and RTL
/// rendering is covered in `test/core/localization_test.dart`, and
/// `test/features/inspections/rtl_layout_test.dart` covers direction-specific
/// layout on these screens specifically.
/// A signed-in buyer, for the screens that need one.
///
/// `create` reads the client id off the auth state, and the create form is the
/// main thing these tests drive — so a signed-out stub would make every
/// successful-submit test fail for a reason that has nothing to do with the
/// form.
const UserProfile _signedInBuyer = UserProfile(
  id: 'user-1',
  fullName: 'Nadia Hassan',
  email: 'nadia@example.com',
  role: UserRole.client,
);

class _StubAuthController extends AuthController {
  @override
  Future<UserProfile?> build() async => _signedInBuyer;
}

Widget _app(
  FakeInspectionRepository repository, {
  required Widget child,
  Locale locale = const Locale('en'),
}) => ProviderScope(
  overrides: [
    inspectionRepositoryProvider.overrideWithValue(repository),
    authControllerProvider.overrideWith(_StubAuthController.new),
    localeProvider.overrideWithValue(locale),
    // The create form asks for the city via the canonical-city picker, which
    // reads the city list; overridden so the picker never reaches a network.
    citiesProvider.overrideWith((Ref ref) async => testCities),
  ],
  child: MaterialApp(
    locale: locale,
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  ),
);

/// The three screens under one router, so navigation between them is exercised
/// rather than stubbed.
Widget _flowApp(FakeInspectionRepository repository) => ProviderScope(
  overrides: [
    inspectionRepositoryProvider.overrideWithValue(repository),
    authControllerProvider.overrideWith(_StubAuthController.new),
    localeProvider.overrideWithValue(const Locale('en')),
    citiesProvider.overrideWith((Ref ref) async => testCities),
  ],
  child: MaterialApp.router(
    locale: const Locale('en'),
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const ClientDashboardPage()),
        GoRoute(
          path: '/requests',
          // Names, not just paths, because the pages navigate with
          // `pushNamed`. A test router without them fails on the first tap with
          // an assertion inside go_router rather than anything to do with the
          // screen under test.
          name: 'myRequests',
          builder: (_, _) => const MyRequestsPage(),
        ),
        GoRoute(
          path: '/requests/new',
          name: 'createRequest',
          builder: (_, _) => const CreateRequestPage(),
        ),
        GoRoute(
          path: '/requests/:id',
          name: 'requestDetail',
          builder: (_, GoRouterState state) =>
              RequestDetailPage(id: state.pathParameters['id'] ?? ''),
        ),
      ],
    ),
  ),
);

/// Pumps [app] on a surface tall enough to hold the whole create form.
///
/// Not cosmetic. The default test surface is 800x600, the create form is far
/// taller than that, and a `ListView` only builds children near the viewport —
/// so a submit button below the fold is not merely invisible, it is not in the
/// tree, and `find` reports zero candidates. Scrolling to each field instead
/// would work but reads as noise in every test and hides which assertions are
/// about behaviour.
Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1000, 3400);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

void main() {
  group('ClientDashboardPage', () {
    testWidgets('with no active request, invites one to be made', (
      WidgetTester tester,
    ) async {
      await _pump(tester,   _app(FakeInspectionRepository(), child: const ClientDashboardPage()));

      expect(find.text('No active request'), findsOneWidget);
      // The design's green band breaks its own action over two lines — `اطلب +
      // الآن` — so the label is a two-line string and a finder built from the
      // flattened form finds nothing.
      expect(find.text('Request\nnow'), findsOneWidget);
    });

    testWidgets('shows the active request by its reference number', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repo = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(referenceNo: 9920, status: InspectionStatus.inProgress),
        ],
      );

      await _pump(tester,   _app(repo, child: const ClientDashboardPage()));

      // The reference leads the card: it is what the buyer reads out to an
      // inspector, so it is the one string that has to be findable. It appears
      // inside the design's `متابعة الطلب النشط طلب #MN-9920` heading rather
      // than alone, so the finder is a substring one.
      expect(find.textContaining('MN-9920'), findsOneWidget);
      expect(find.text('Toyota Corolla (2019)'), findsOneWidget);
    });

    testWidgets('shows the invoice as three lines and a total', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repo = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(
            status: InspectionStatus.accepted,
            centre: 'Kartek Centre',
            centreFee: 300,
            appointmentAt: DateTime.utc(2026, 9, 20, 10),
          ),
        ],
      );

      await _pump(tester,   _app(repo, child: const ClientDashboardPage()));

      expect(find.text('Invoice and cost details'), findsOneWidget);
      // The design's three lines, each bulleted: the centre's own fee (named,
      // because one has been chosen), the inspector's, and the platform's. The
      // bullet is part of the line the design prints, not decoration on the
      // widget, so it belongs in the expected text.
      expect(
        find.text('• Approved centre inspection (Kartek Centre)'),
        findsOneWidget,
      );
      expect(
        find.text('• Inspector fee (coordination and follow-up)'),
        findsOneWidget,
      );
      expect(
        find.text('• Moaen platform fee (documentation and tracking)'),
        findsOneWidget,
      );
      expect(find.text('Total inclusive:'), findsOneWidget);
      // The buyer's own budget, split by the commission: 451 to the inspector, 49 to
      // the platform, and the 300 the centre charges on top. The budget is no longer
      // a platform figure the client has no say over, so it is not printed here —
      // it is the sum of two of these lines, and a client reading four numbers to
      // check three is a client doing arithmetic the app should be doing.
      expect(find.text('300 ر.س'), findsOneWidget);
      expect(find.text('451 ر.س'), findsOneWidget);
      expect(find.text('49 ر.س'), findsOneWidget);
      // 300 + 500. `agreed_total` is 500 because the commission splits the budget
      // alone; the centre's fee is a pass-through the invoice adds on top.
      expect(find.text('800 ر.س'), findsOneWidget);
    });

    testWidgets('an unbooked invoice says the centre fee is still to come', (
      WidgetTester tester,
    ) async {
      // A total printed before the inspector has chosen a centre would be a
      // quote for something nobody has agreed to. The design says so instead of
      // showing a zero, which would read as free.
      await _pump(tester,   _app(
          FakeInspectionRepository(
            requests: <InspectionRequest>[
              buildRequest(status: InspectionStatus.accepted),
            ],
          ),
          child: const ClientDashboardPage(),
        ));

      // Matched without the leading emoji, which the console renders as `?` and
      // which is decoration on the sentence rather than part of it.
      expect(
        find.textContaining('Set after the inspector chooses the centre'),
        findsOneWidget,
      );
      // The budget's own split, which exists as soon as the job is claimed: 451 to
      // the inspector, 49 to the platform, 500 all told. The centre's fee is the
      // line that is still to come, so it is named as such rather than left out —
      // and the total is the 500 alone, because the centre's fee is not yet a number
      // the platform can invoice.
      expect(find.text('451 ر.س'), findsOneWidget);
      expect(find.text('49 ر.س'), findsOneWidget);
      expect(find.text('500 ر.س'), findsOneWidget);
    });

    testWidgets('the progress track advances with the status', (
      WidgetTester tester,
    ) async {
      // Counted from the request's own columns, not from `status`. The design
      // paints a centre chosen and an appointment made as two separate finished
      // steps, so an `accepted` request that has been booked is genuinely two
      // steps further on than one that has not — and the status column has not
      // caught up. Asserting only on `status` would let that distinction rot.
      final booked = (
        centre: 'Kartek Centre',
        centreFee: 300.0,
        appointmentAt: DateTime.utc(2026, 9, 20, 10),
      );
      for (final (
        InspectionStatus status,
        int expectedReached,
        String label,
      ) in <(InspectionStatus, int, String)>[
        (InspectionStatus.pending, 0, 'pending: nobody has acted yet'),
        (InspectionStatus.accepted, 1, 'accepted: the inspector is assigned'),
        (InspectionStatus.inProgress, 3, 'in progress: booked and under way'),
        (InspectionStatus.completed, 4, 'completed: all four steps done'),
      ]) {
        await _pump(tester,           _app(
            FakeInspectionRepository(
              requests: <InspectionRequest>[buildRequest(status: status)],
            ),
            child: const ClientDashboardPage(),
          ));

        // Every step label is present at every status; what changes is how many
        // are ticked. A check-mark icon per completed step is the signal.
        expect(
          find.byIcon(Icons.check),
          findsNWidgets(expectedReached),
          reason: '$label, so it should have $expectedReached ticked step(s)',
        );
      }

      // The same status, booked and not booked. Without this case the counts
      // above would pass against a tracker that read `status` alone, and the
      // coordination step would silently mean nothing.
      for (final (bool bookedCentre, int expectedReached) in <(bool, int)>[
        (false, 1),
        (true, 2),
      ]) {
        await _pump(tester,           _app(
            FakeInspectionRepository(
              requests: <InspectionRequest>[
                buildRequest(
                  status: InspectionStatus.accepted,
                  centre: bookedCentre ? booked.centre : null,
                  centreFee: bookedCentre ? booked.centreFee : null,
                  appointmentAt: bookedCentre ? booked.appointmentAt : null,
                ),
              ],
            ),
            child: const ClientDashboardPage(),
          ));

        expect(
          find.byIcon(Icons.check),
          findsNWidgets(expectedReached),
          reason: 'accepted ${bookedCentre ? 'with' : 'without'} a centre booked '
              'should reach $expectedReached step(s)',
        );
      }
    });

    testWidgets('a cancelled request shows no progress track', (
      WidgetTester tester,
    ) async {
      await _pump(tester,         _app(
          FakeInspectionRepository(
            requests: <InspectionRequest>[
              buildRequest(status: InspectionStatus.cancelled),
            ],
          ),
          child: const ClientDashboardPage(),
        ));

      expect(find.text('Cancelled'), findsWidgets);
      // Four grey numbered circles would read as a queue the work is sitting in.
      // The request is not in a queue; it was withdrawn.
      expect(find.byIcon(Icons.check), findsNothing);
      expect(
        find.text('Full inspection at the centre'),
        findsNothing,
        reason: 'a cancelled request must not draw the four-step tracker',
      );
    });

    testWidgets('a failed load offers a retry rather than a blank screen', (
      WidgetTester tester,
    ) async {
      await _pump(tester,         _app(
          FakeInspectionRepository(failure: const InspectionFailure('boom')),
          child: const ClientDashboardPage(),
        ));

      expect(find.text('No active request'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
  group('CreateRequestPage', () {
    testWidgets('refuses to submit an empty form', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repo = FakeInspectionRepository();
      await _pump(tester, _app(repo, child: const CreateRequestPage()));

      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(repo.createdDrafts, isEmpty);
      // Six fields carry a validator: make, model, year, seller name, seller
      // phone and city. The plate, the listing link and the notes are all
      // optional and report nothing. The count is asserted rather than
      // membership so that a field added without a validator — which would let an
      // empty request through — fails here.
      expect(find.text('This field is required'), findsNWidgets(6));
    });

    testWidgets('rejects a year outside the schema bound', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repo = FakeInspectionRepository();
      await _pump(tester, _app(repo, child: const CreateRequestPage()));

      await _fillValidForm(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, _yearHint),
        '1949',
      );
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(repo.createdDrafts, isEmpty);
      expect(find.text('Enter a year between 1950 and 2100'), findsOneWidget);
    });

    testWidgets('sends the draft the buyer filled in', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repo = FakeInspectionRepository();
      await _pump(tester, _app(repo, child: const CreateRequestPage()));

      await _fillValidForm(tester);
      await _selectCity(tester, 'Jeddah');
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(repo.createdDrafts, hasLength(1));
      final InspectionDraft sent = repo.createdDrafts.single;
      expect(sent.carMake, 'Toyota');
      expect(sent.carModel, 'FJ');
      expect(sent.carYear, '2023');
      expect(sent.sellerName, 'Abu Fahad');
      expect(sent.sellerPhone, '0501234567');
      expect(sent.city, 'Jeddah');
      expect(sent.clientNotes, 'Call before going');
      // No address and no budget: the design removed both inputs, so a draft can
      // only ever carry the car's three fields, the seller's two and the city.
      // The row's `price` is the estimate, written by `toRow`.
      expect(sent.sellerLocationAddress, isEmpty);
      expect(sent.clientName, 'Nadia Hassan');
    });

    testWidgets('the budget breaks into the inspector share and the platform fee', (
      WidgetTester tester,
    ) async {
      await _pump(tester,   _app(FakeInspectionRepository(), child: const CreateRequestPage()));

      // The budget is now the buyer's own figure, and the two lines under it are the
      // split of *that* number — not the platform's standing 150 + 49. On the default
      // budget of 500 with the seeded 49 fixed fee, the inspector's share is 451.
      expect(find.text('500'), findsOneWidget);
      expect(find.text('451 ر.س'), findsOneWidget);
      expect(find.text('49 ر.س'), findsOneWidget);
      // The centre's is still the one line the buyer cannot be quoted: the inspector
      // picks the centre during the coordination window, so the total names it as
      // still-to-come rather than showing a zero that would read as free.
      expect(find.text('199 ر.س + centre fee'), findsNothing);
      expect(find.text('500 ر.س + centre fee'), findsOneWidget);

      // Re-typing the budget re-splits the two lines underneath it, on every
      // keystroke and not only on submit — a breakdown that appeared after a failed
      // submit would be a breakdown of the wrong number.
      await tester.enterText(
        _budgetField,
        '1000',
      );
      await tester.pumpAndSettle();

      expect(find.text('951 ر.س'), findsOneWidget);
      expect(find.text('49 ر.س'), findsOneWidget);
    });

    testWidgets('a budget outside the accepted range is refused with its bound', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repo = FakeInspectionRepository();
      await _pump(tester,   _app(repo, child: const CreateRequestPage()));

      // Below the floor. The message names the floor rather than saying "invalid",
      // because "invalid" tells a buyer nothing about which end of the range they
      // are on the wrong side of.
      await tester.enterText(_budgetField, '20');
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(find.text('Enter at least 50 SAR.'), findsOneWidget);

      // Above the ceiling, with the other bound named. Both ends are checked against
      // the column's own constraint, which is why the numbers in the messages are
      // [CostEstimate]'s rather than literals — a message that disagreed with the
      // database would tell a buyer a limit it does not have.
      await tester.enterText(_budgetField, '100001');
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(find.text('Enter no more than 100000 SAR.'), findsOneWidget);

      // Neither reached the repository. The form is the only thing that decides a
      // budget is unacceptable; if the write were attempted and then refused, the
      // buyer would see a server error for what is a field-level mistake.
      expect(repo.createdDrafts, isEmpty);
    });

    testWidgets('a non-numeric budget is refused before the repository is called', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repo = FakeInspectionRepository();
      await _pump(tester, _app(repo, child: const CreateRequestPage()));

      // The letters case: a buyer who pasted `500SAR` is not to be told the range,
      // they are to be told to drop the letters. Two different mistakes get two
      // different sentences for exactly this reason.
      await tester.enterText(_budgetField, '500SAR');
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a number.'), findsOneWidget);
      expect(repo.createdDrafts, isEmpty);
    });

    testWidgets('notes are optional', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repo = FakeInspectionRepository();
      await _pump(tester, _app(repo, child: const CreateRequestPage()));

      await _fillValidForm(tester, withNotes: false);
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(repo.createdDrafts, hasLength(1));
      expect(repo.createdDrafts.single.clientNotes, isEmpty);
    });

    testWidgets('surfaces a failure from the repository', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repo = FakeInspectionRepository()
        ..createFailure = const InspectionFailure(
          'Some details were rejected by the server.',
        );

      await _pump(tester, _app(repo, child: const CreateRequestPage()));

      await _fillValidForm(tester);
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(find.text('Some details were rejected by the server.'), findsOneWidget);
    });
  });

  group('MyRequestsPage', () {
    testWidgets('says so when there are none', (
      WidgetTester tester,
    ) async {
      await _pump(tester,   _app(FakeInspectionRepository(), child: const MyRequestsPage()));

      expect(
        find.text('You have not requested an inspection yet.'),
        findsOneWidget,
      );
    });

    testWidgets('separates open work from settled work', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repo = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(
            id: 'open-1',
            referenceNo: 1001,
            status: InspectionStatus.inProgress,
          ),
          buildRequest(
            id: 'done-1',
            referenceNo: 1002,
            status: InspectionStatus.completed,
          ),
        ],
      );

      await _pump(tester, _app(repo, child: const MyRequestsPage()));

      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Settled'), findsOneWidget);
      // Both rows are listed; the split is by header, not by omission.
      expect(find.text('MN-1001'), findsOneWidget);
      expect(find.text('MN-1002'), findsOneWidget);
    });

    testWidgets('renders the status of each row', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repo = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(
            id: 'a',
            referenceNo: 1001,
            status: InspectionStatus.pending,
          ),
          buildRequest(
            id: 'b',
            referenceNo: 1002,
            status: InspectionStatus.completed,
          ),
        ],
      );

      await _pump(tester, _app(repo, child: const MyRequestsPage()));

      expect(find.text('Awaiting inspector'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
    });

    testWidgets('a failed load is retryable', (
      WidgetTester tester,
    ) async {
      await _pump(tester,         _app(
          FakeInspectionRepository(failure: const InspectionFailure('boom')),
          child: const MyRequestsPage(),
        ));

      expect(find.text('Could not load the data. Please try again.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('RequestDetailPage', () {
    testWidgets('shows the request it was given', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repo = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(referenceNo: 9920, notes: 'Seller is impatient.'),
        ],
      );

      await _pump(tester,   _app(repo, child: const RequestDetailPage(id: 'req-1')));

      expect(find.text('MN-9920'), findsOneWidget);
      expect(find.text('Toyota'), findsOneWidget);
      expect(find.text('Corolla'), findsOneWidget);
      expect(find.text('+201000000001'), findsOneWidget);
      expect(find.text('Seller is impatient.'), findsOneWidget);
    });

    testWidgets('cancels only after the buyer confirms', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repo = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(id: 'req-1', status: InspectionStatus.pending),
        ],
      );

      await _pump(tester,   _app(repo, child: const RequestDetailPage(id: 'req-1')));

      await tester.tap(find.text('Cancel request'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this request?'), findsOneWidget);

      // Backing out must not cancel. Cancelling is irreversible and moves a real
      // transaction, so the default has to be the safe answer.
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();

      expect(repo.cancelledIds, isEmpty);
    });

    testWidgets('cancels on confirmation and reports it', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repo = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(id: 'req-1', status: InspectionStatus.pending),
        ],
      );

      await _pump(tester,   _app(repo, child: const RequestDetailPage(id: 'req-1')));

      await tester.tap(find.text('Cancel request'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel request'));
      await tester.pumpAndSettle();

      expect(repo.cancelledIds, <String>['req-1']);
      expect(find.text('Request cancelled.'), findsOneWidget);
    });

    testWidgets('a settled request offers no cancel action', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repo = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(id: 'req-1', status: InspectionStatus.completed),
        ],
      );

      await _pump(tester,   _app(repo, child: const RequestDetailPage(id: 'req-1')));

      // Cancelling a completed inspection would mean unwinding a finished
      // report, which is not what the buyer is being offered.
      expect(find.text('Cancel request'), findsNothing);
    });
  });

  group('the flow end to end', () {
    testWidgets('a new request appears in the list with its assigned number', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repo = FakeInspectionRepository();
      await _pump(tester, _flowApp(repo));

      expect(find.text('No active request'), findsOneWidget);

      // Two lines in the design, so two lines in the finder.
      await tester.tap(find.text('Request\nnow'));
      await tester.pumpAndSettle();
      expect(find.byType(CreateRequestPage), findsOneWidget);

      await _fillValidForm(tester);
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      // The form pops, and the dashboard now shows the row the database
      // returned — reference included, which is the whole point of 0004. The
      // reference appears inside the design's `متابعة الطلب النشط طلب #MN-1001`
      // heading rather than on its own, so the finder is a substring one.
      expect(find.byType(CreateRequestPage), findsNothing);
      expect(find.textContaining('MN-1001'), findsOneWidget);
    });
  });
}

/// Fills the required fields, and optionally the notes field.
///
/// Every field is found by its *hint* rather than its label, because the design
/// puts the label in a [FieldLabel] above the field and the hint inside it — so
/// `widgetWithText(TextFormField, label)` would find nothing. The city is the
/// exception: it is a [CityPicker], not a text field, and has no hint at all.
Future<void> _fillValidForm(
  WidgetTester tester, {
  bool withNotes = true,
}) async {
  Future<void> enter(String hint, String value) =>
      tester.enterText(find.widgetWithText(TextFormField, hint), value);

  await enter(_makeHint, 'Toyota');
  await enter(_modelHint, 'FJ');
  await enter(_yearHint, '2023');
  await enter(_sellerPhoneHint, '0501234567');
  await _selectCity(tester, 'Dammam');
  await enter(_sellerNameHint, 'Abu Fahad');
  if (withNotes) await enter(_notesHint, 'Call before going');
  await tester.pumpAndSettle();
}

/// Chooses a city through the canonical-city picker: taps the field to open the
/// sheet, then the option. The field may be below the fold on a tall form, so it
/// is scrolled into view first — `tap` on an off-screen target silently does
/// nothing.
Future<void> _selectCity(WidgetTester tester, String city) async {
  await tester.ensureVisible(find.byType(CityPicker));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(CityPicker));
  await tester.pumpAndSettle();

  await tester.tap(find.text(city).last);
  await tester.pumpAndSettle();
}

/// The `hintText` on each field in the create form.
///
/// Named rather than inlined, because a finder built from the field's *value*
/// instead of its hint is a mistake that compiles and fails at runtime, and these
/// are long enough to be easy to mistype. They mirror `app_en.arb`; a wording
/// change there fails these tests loudly rather than silently skipping a field.
const String _makeHint = 'e.g. Toyota FJ';
const String _modelHint = 'e.g. FJ';
const String _yearHint = 'e.g. 2023';
const String _sellerNameHint = 'e.g. Abu Fahad';
const String _sellerPhoneHint = '05xxxxxxxx';
const String _notesHint =
    'e.g. Please check the front bumper repaint or the air conditioning...';

/// The create form's budget field.
///
/// Scoped by its [CostBox] rather than found by value: every other field on this
/// form is identified by its hint, but the budget is *prefilled* with
/// `CostEstimate.defaultBudget`, so there is no hint showing and a value-based
/// finder would stop matching the moment a test retyped it — which is exactly what
/// the tests that re-type it are for. `CostBox` is the one widget on this form that
/// contains the budget field and no other text field.
final Finder _budgetField = find.descendant(
  of: find.byType(CostBox),
  matching: find.byType(TextFormField),
);
