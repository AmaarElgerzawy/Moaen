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
import 'package:moaen/l10n/gen/app_localizations.dart';

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
      expect(find.text('Request an inspection'), findsWidgets);
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
      // inspector, so it is the one string that has to be findable.
      expect(find.text('MN-9920'), findsOneWidget);
      expect(find.text('Toyota Corolla 2019'), findsOneWidget);
    });

    testWidgets('shows the cost breakdown and calls it an estimate', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repo = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(price: 500, status: InspectionStatus.pending),
        ],
      );

      await _pump(tester,   _app(repo, child: const ClientDashboardPage()));

      expect(find.text('Cost estimate'), findsOneWidget);
      expect(find.text('Inspection fee'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('500 EGP'), findsNWidgets(2));

      // The distinction matters: a total shown without this reads as a charge
      // that has already happened, when it is a budget the buyer stated.
      expect(
        find.textContaining('The final price is agreed with the inspector'),
        findsOneWidget,
      );
    });

    testWidgets('the progress track advances with the status', (
      WidgetTester tester,
    ) async {
      for (final (InspectionStatus status, int expectedReached) in <(
        InspectionStatus,
        int,
      )>[
        (InspectionStatus.pending, 1),
        (InspectionStatus.accepted, 2),
        (InspectionStatus.inProgress, 3),
        (InspectionStatus.completed, 4),
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
          reason: '$status should have $expectedReached completed step(s)',
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
      // Four unfilled dots would imply the work is merely late.
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.text('Progress'), findsNothing);
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
      // Seven fields carry a validator: make, model, year, seller phone,
      // address, city and budget. Notes is optional and reports nothing. The
      // count is asserted rather than membership so that a field added without
      // a validator — which would let an empty request through — fails here.
      expect(find.text('This field is required'), findsNWidgets(7));
    });

    testWidgets('rejects a year outside the schema bound', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repo = FakeInspectionRepository();
      await _pump(tester, _app(repo, child: const CreateRequestPage()));

      await _fillValidForm(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, _year),
        '1949',
      );
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(repo.createdDrafts, isEmpty);
      expect(find.text('Enter a year between 1950 and 2100'), findsOneWidget);
    });

    testWidgets('rejects a budget that is not a number', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repo = FakeInspectionRepository();
      await _pump(tester, _app(repo, child: const CreateRequestPage()));

      await _fillValidForm(tester);
      // The formatter keeps this to digits and one point, so this is what a
      // buyer can actually end up with.
      await tester.enterText(
        find.widgetWithText(TextFormField, _budget),
        '5.',
      );
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(repo.createdDrafts, isEmpty);
      expect(find.text('Enter an amount, for example 500'), findsOneWidget);
    });

    testWidgets('sends the draft the buyer filled in', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository repo = FakeInspectionRepository();
      await _pump(tester, _app(repo, child: const CreateRequestPage()));

      await _fillValidForm(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, _city),
        'Giza',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, _budget),
        '750',
      );
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(repo.createdDrafts, hasLength(1));
      final InspectionDraft sent = repo.createdDrafts.single;
      expect(sent.carMake, 'Toyota');
      expect(sent.carModel, 'Corolla');
      expect(sent.carYear, '2019');
      expect(sent.sellerPhone, '+201000000001');
      expect(sent.sellerLocationAddress, '12 Nile Street');
      expect(sent.city, 'Giza');
      expect(sent.clientNotes, 'Call before going');
      expect(sent.budgetAmount, 750.0);
    });

    testWidgets('the running total follows the budget the buyer types', (
      WidgetTester tester,
    ) async {
      await _pump(tester,   _app(FakeInspectionRepository(), child: const CreateRequestPage()));

      // Before anything is typed, the platform's estimate stands in.
      expect(find.text('500 EGP'), findsNWidgets(2));

      await tester.enterText(
        find.widgetWithText(TextFormField, _budget),
        '750',
      );
      await tester.pumpAndSettle();

      // The buyer's own budget takes over as soon as they state one.
      expect(find.text('750 EGP'), findsNWidgets(2));
      expect(find.text('500 EGP'), findsNothing);
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

      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
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

      await tester.tap(find.text('Request an inspection').first);
      await tester.pumpAndSettle();
      expect(find.byType(CreateRequestPage), findsOneWidget);

      await _fillValidForm(tester);
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      // The form pops, and the dashboard now shows the row the database
      // returned — reference included, which is the whole point of 0004.
      expect(find.byType(CreateRequestPage), findsNothing);
      expect(find.text('MN-1001'), findsOneWidget);
    });
  });
}

/// Fills the required fields, and optionally the notes field.
Future<void> _fillValidForm(
  WidgetTester tester, {
  bool withNotes = true,
}) async {
  Future<void> enter(String label, String value) =>
      tester.enterText(find.widgetWithText(TextFormField, label), value);

  await enter(_make, 'Toyota');
  await enter(_model, 'Corolla');
  await enter(_year, '2019');
  await enter(_phone, '+201000000001');
  await enter(_address, '12 Nile Street');
  await enter(_city, 'Cairo');
  await enter(_budget, '500');
  if (withNotes) await enter(_notes, 'Call before going');
  await tester.pumpAndSettle();
}

/// The `labelText` on each field in the create form.
///
/// Named rather than inlined, because a finder built from the field's *value*
/// instead of its label is a mistake that compiles and fails at runtime, and
/// these are long enough to be easy to mistype. They mirror `app_en.arb`; a
/// wording change there fails these tests loudly rather than silently skipping
/// a field.
const String _make = 'Make';
const String _model = 'Model';
const String _year = 'Year';
const String _phone = 'Seller phone';
const String _address = 'Where is the car?';
const String _city = 'City';
const String _budget = 'Your budget (EGP)';

/// The notes field is labelled by its instruction, which doubles as its hint.
/// There is no short label to find it by.
const String _notes =
    'Anything the inspector should know: when the car can be seen, '
    'what looks wrong, how trustworthy the seller is.';
