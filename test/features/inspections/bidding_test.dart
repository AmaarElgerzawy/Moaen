import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moaen/core/localization/locale_provider.dart';
import 'package:moaen/core/theme/app_theme.dart';
import 'package:moaen/features/auth/auth_controller.dart';
import 'package:moaen/features/auth/user_profile.dart';
import 'package:moaen/features/cities/application/city_controller.dart';
import 'package:moaen/features/inspections/application/inspection_controller.dart';
import 'package:moaen/features/inspections/data/inspection_repository.dart';
import 'package:moaen/features/inspections/domain/inspection_bid.dart';
import 'package:moaen/features/inspections/domain/inspection_request.dart';
import 'package:moaen/features/inspections/presentation/inspector_job_detail_page.dart';
import 'package:moaen/features/inspections/presentation/request_detail_page.dart';
import 'package:moaen/features/inspections/presentation/widgets/design_widgets.dart';
import 'package:moaen/l10n/gen/app_localizations.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_bid_repository.dart';
import '../../support/fake_cities.dart';
import '../../support/fake_inspection_repository.dart';

/// The negotiation, from both sides.
///
/// Two halves, and the halves are the point: an inspector who can see only their own
/// net and a buyer who can see only the total would each be guessing about the other
/// number, and the whole safety of the arrangement is that *neither* of them set
/// either. So every figure in these tests comes off a row the trigger wrote, and the
/// assertion is on what the screen shows rather than on what it sent.
///
/// The buyer's default budget is 500 and the seeded commission is a flat 49, so the
/// inspector's share of an unnegotiated job is 451 and an offer of 200 puts the
/// buyer's total at 249.
const UserProfile _inspector = UserProfile(
  id: 'inspector-1',
  fullName: 'Karim Adel',
  email: 'karim@example.com',
  role: UserRole.inspector,
  locationCity: 'Dammam',
);

class _InspectorAuth extends AuthController {
  @override
  Future<UserProfile?> build() async => _inspector;
}

/// Pumps the negotiation's screens on a surface tall enough for all of them.
///
/// Not cosmetic: the default test surface is 800x600, both pages are far taller, and
/// a lazy list only builds children near the viewport — so the offer button at the
/// foot of the earnings card would not merely be invisible, it would not be in the
/// tree, and `find` would report zero candidates for it.
Future<void> _pump(
  WidgetTester tester, {
  required FakeInspectionRepository inspections,
  required FakeBidRepository bids,
  required Widget child,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1000, 3200);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inspectionRepositoryProvider.overrideWithValue(inspections),
        bidRepositoryProvider.overrideWithValue(bids),
        authControllerProvider.overrideWith(_InspectorAuth.new),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(profile: _inspector, userId: _inspector.id),
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

/// A claimed job with the split the trigger wrote, as the fake's `accept` would.
InspectionRequest _claimed({
  BidStatus bidStatus = BidStatus.none,
  String? counterNote,
  double? inspectorNet,
  double? agreedTotal,
}) => buildRequest(
  id: 'req-1',
  inspectorId: 'inspector-1',
  inspectorName: 'Karim Adel',
  status: InspectionStatus.accepted,
  centre: 'Kartek Centre',
  centreFee: 300,
  appointmentAt: DateTime.utc(2026, 9, 20, 10),
  inspectorNet: inspectorNet,
  agreedTotal: agreedTotal,
  bidStatus: bidStatus,
  counterNote: counterNote,
);

void main() {
  group('inspector counter-offers', () {
    testWidgets('a claimed job shows the earnings the budget left them', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository inspections = FakeInspectionRepository(
        requests: <InspectionRequest>[_claimed()],
      );
      await _pump(
        tester,
        inspections: inspections,
        bids: FakeBidRepository(),
        child: const InspectorJobDetailPage(id: 'req-1'),
      );

      // 500 less the 49 commission. Read off `inspector_net`, which the trigger
      // wrote when the job was claimed — not recomputed here, because a screen that
      // recomputed it would agree with the database right up until the commission
      // moved, and then quote a number the database would refuse.
      expect(find.text('451 ر.س'), findsOneWidget);
      // And the total the buyer pays, so the two numbers are on one screen and the
      // inspector can see that the fee exists rather than wondering where 49 went.
      expect(find.text('500 ر.س'), findsOneWidget);
      // Named as an opening position, not a settled one: nothing has been negotiated.
      expect(find.text("The same as the buyer's budget"), findsOneWidget);
    });

    testWidgets('an unclaimed job shows no earnings card at all', (
      WidgetTester tester,
    ) async {
      // Nothing to quote against and nothing to earn yet. A card with zeroes on it
      // would be a card telling an inspector they have earned nothing on a job they
      // have not taken — and the offer button would be one the database refuses.
      final FakeInspectionRepository inspections = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(status: InspectionStatus.pending),
        ],
      );
      await _pump(
        tester,
        inspections: inspections,
        bids: FakeBidRepository(),
        child: const InspectorJobDetailPage(id: 'req-1'),
      );

      expect(find.text('Your share of the budget'), findsNothing);
      expect(find.text('Offer a different amount'), findsNothing);
    });

    testWidgets('an offer of 200 sends a net, not a total', (
      WidgetTester tester,
    ) async {
      final FakeBidRepository bids = FakeBidRepository();
      await _pump(
        tester,
        inspections: FakeInspectionRepository(
          requests: <InspectionRequest>[_claimed()],
        ),
        bids: bids,
        child: const InspectorJobDetailPage(id: 'req-1'),
      );

      await tester.tap(find.text('Offer a different amount'));
      await tester.pumpAndSettle();

      // The sheet opens on the net the claim already earned, so opening it and
      // closing it changes nothing.
      expect(find.text('Your earnings'), findsOneWidget);
      expect(find.text('451'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, '200');
      await tester.pumpAndSettle();
      // The buyer pays the net *plus* the fee, and the sheet says so before the
      // offer is sent — an inspector quoting 200 who is not told that would read
      // 249 as an error and try to subtract the fee again.
      expect(find.text('249 ر.س'), findsOneWidget);
      expect(
        find.text("The buyer's total is this amount plus the platform fee."),
        findsOneWidget,
      );

      await tester.tap(find.text('Send offer'));
      await tester.pumpAndSettle();

      // The insert carries the job, the net and — when there is one — the note. A
      // total, a fee, a round or a status in here would be a client choosing a number
      // `seal_bid` owns, which is the one thing this feature must make impossible.
      expect(bids.inserts, hasLength(1));
      expect(
        bids.inserts.single.keys,
        containsAll(<String>['inspection_id', 'net_amount']),
      );
      expect(
        bids.inserts.single.keys,
        isNot(
          containsAll(<String>[
            'total_amount',
            'platform_fee',
            'round',
            'status',
            'inspector_id',
          ]),
        ),
      );
      // What the *sealed* row came to, which the client never saw: the 200 net plus
      // the 49 commission the trigger added. Asserted because a fake that echoed the
      // net back as the total would let a real bug through.
      expect(bids.inserts.single['net_amount'], 200);
    });

    testWidgets(
      'an offer below zero is refused before the repository is called',
      (WidgetTester tester) async {
        final FakeBidRepository bids = FakeBidRepository();
        await _pump(
          tester,
          inspections: FakeInspectionRepository(
            requests: <InspectionRequest>[_claimed()],
          ),
          bids: bids,
          child: const InspectorJobDetailPage(id: 'req-1'),
        );

        await tester.tap(find.text('Offer a different amount'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).first, '0');
        await tester.pumpAndSettle();

        // The send button stays *enabled* on a parsable zero — the range check runs
        // on the way out rather than greying the button out, because a dead button
        // with no explanation is the worse of the two ways to refuse input.
        await tester.tap(find.text('Send offer'));
        await tester.pumpAndSettle();

        expect(
          find.text('Enter an amount between 1 and 100000 SAR.'),
          findsOneWidget,
        );
        // And the sheet stays open with the figure still in it, so an inspector who
        // mistyped has not lost their place to fix it.
        expect(find.text('Send offer'), findsOneWidget);
        expect(bids.inserts, isEmpty);
      },
    );

    testWidgets('a second offer is a second round, and the first is closed', (
      WidgetTester tester,
    ) async {
      final FakeBidRepository bids = FakeBidRepository()
        // A first round the buyer already refused.
        ..seed('req-1', net: 200, round: 1, status: BidStatus.declined);

      await _pump(
        tester,
        inspections: FakeInspectionRepository(
          requests: <InspectionRequest>[
            _claimed(
              bidStatus: BidStatus.declined,
              counterNote: 'Too much, that is over my budget.',
            ),
          ],
        ),
        bids: bids,
        child: const InspectorJobDetailPage(id: 'req-1'),
      );

      // The reason the buyer gave, handed back to the inspector. Without it a second
      // round is the same offer again.
      expect(
        find.text(
          'Your reason for declining: Too much, that is over my budget.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Offer a different amount'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '300');
      await tester.tap(find.text('Send offer'));
      await tester.pumpAndSettle();

      final List<InspectionBid> offers = bids.offersByInspection['req-1']!;
      // Round two, not one: an attempt that was refused still counted, and offering
      // "round one" again would tell the buyer a negotiation restarted rather than
      // continued.
      expect(offers.map((InspectionBid b) => b.round), contains(2));
    });

    testWidgets(
      'an open offer hides the button rather than letting it be replaced',
      (WidgetTester tester) async {
        // `seal_bid` supersedes a pending offer silently. A button that quietly threw
        // the buyer's open question away and asked another would be worse than no
        // button: the only way back is for the buyer to refuse, which is their
        // decision to make.
        final FakeBidRepository bids = FakeBidRepository()
          ..seed('req-1', net: 200, round: 1);

        await _pump(
          tester,
          inspections: FakeInspectionRepository(
            requests: <InspectionRequest>[_claimed()],
          ),
          bids: bids,
          child: const InspectorJobDetailPage(id: 'req-1'),
        );

        expect(find.text('Offer a different amount'), findsNothing);
        expect(find.textContaining('Offer 1'), findsOneWidget);
        expect(find.text('Offer awaiting an answer'), findsOneWidget);
      },
    );
  });

  group('buyer answers', () {
    testWidgets('an open offer is shown with the split and two answers', (
      WidgetTester tester,
    ) async {
      final FakeBidRepository bids = FakeBidRepository()
        ..seed('req-1', net: 200, note: 'This car needs a full day.');

      await _pump(
        tester,
        inspections: FakeInspectionRepository(
          requests: <InspectionRequest>[_claimed()],
        ),
        bids: bids,
        child: const RequestDetailPage(id: 'req-1'),
      );

      expect(
        find.text('The inspector asked for 249 ر.س instead of 500 ر.س.'),
        findsOneWidget,
      );

      // Scoped to the offer card rather than the page, because the settled figures
      // below it print the same 49 for the same commission — and a page-wide count
      // would be asserting that a coincidence holds.
      final Finder card = find.ancestor(
        of: find.text('Accept'),
        matching: find.byType(NoticeBox),
      );
      // The split, so the buyer is deciding about the fee rather than taking it on
      // trust.
      expect(
        find.descendant(of: card, matching: find.text('200 ر.س')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('49 ر.س')),
        findsOneWidget,
      );
      // And the inspector's sentence, which is usually the real reason.
      expect(find.text('This car needs a full day.'), findsOneWidget);
      // Named for what they are doing — agreeing to a price, not taking the job.
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Keep my budget'), findsOneWidget);
      expect(find.text('Accept inspection'), findsNothing);
    });

    testWidgets('accepting copies the offer onto the inspection', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository inspections = FakeInspectionRepository(
        requests: <InspectionRequest>[_claimed()],
      );
      await _pump(
        tester,
        inspections: inspections,
        bids: FakeBidRepository()..seed('req-1', net: 200),
        child: const RequestDetailPage(id: 'req-1'),
      );

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Agreed, it is a full day.',
      );
      await tester.tap(find.text('Accept').last);
      await tester.pumpAndSettle();

      // One word plus the note. `platform_fee`, `inspector_net`, `agreed_total` and
      // `agreed_at` are never in a client's hands, so there is no way for a buyer to
      // accept at a total they invented.
      expect(inspections.bidAnswers, hasLength(1));
      expect(inspections.bidAnswers.single.accept, isTrue);
      expect(
        inspections.bidAnswers.single.counterNote,
        'Agreed, it is a full day.',
      );
      expect(find.text('Agreed at 249 ر.س.'), findsOneWidget);
    });

    testWidgets('refusing leaves the job claimed and takes the reason', (
      WidgetTester tester,
    ) async {
      final FakeInspectionRepository inspections = FakeInspectionRepository(
        requests: <InspectionRequest>[_claimed()],
      );
      await _pump(
        tester,
        inspections: inspections,
        bids: FakeBidRepository()..seed('req-1', net: 200),
        child: const RequestDetailPage(id: 'req-1'),
      );

      await tester.tap(find.text('Keep my budget'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Too much, that is over my budget.',
      );
      await tester.tap(find.text('Keep my budget').last);
      await tester.pumpAndSettle();

      expect(inspections.bidAnswers.single.accept, isFalse);
      expect(
        inspections.bidAnswers.single.counterNote,
        'Too much, that is over my budget.',
      );
      // A refusal is not a cancellation: the job is still the inspector's, and they
      // may offer again. Cancelling here would take a priced, claimed job off the
      // board because two people disagreed about money.
      expect(inspections.cancelledIds, isEmpty);
      expect(find.text('You declined the offer.'), findsOneWidget);
    });

    testWidgets('dismissing the reason dialog answers nothing', (
      WidgetTester tester,
    ) async {
      // The dialog returning null is a dismissal, and a dismissal is not a refusal.
      // `seal_bid` would happily record a refusal with no reason, so the UI has to
      // be the thing that distinguishes them.
      final FakeInspectionRepository inspections = FakeInspectionRepository(
        requests: <InspectionRequest>[_claimed()],
      );
      await _pump(
        tester,
        inspections: inspections,
        bids: FakeBidRepository()..seed('req-1', net: 200),
        child: const RequestDetailPage(id: 'req-1'),
      );

      await tester.tap(find.text('Keep my budget'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(inspections.bidAnswers, isEmpty);
      // The card is still there, so the buyer can still answer.
      expect(find.text('Keep my budget'), findsOneWidget);
    });

    testWidgets('no offer means no card', (WidgetTester tester) async {
      // A badge reading "no offer" on a request nobody has negotiated is noise, and
      // it is worse than noise here: it invites the buyer to go looking for a
      // counter-offer button that does not exist.
      await _pump(
        tester,
        inspections: FakeInspectionRepository(
          requests: <InspectionRequest>[_claimed()],
        ),
        bids: FakeBidRepository(),
        child: const RequestDetailPage(id: 'req-1'),
      );

      expect(find.text('Accept'), findsNothing);
      expect(find.text('Keep my budget'), findsNothing);
      // The settled figures are still there — under the card rather than beside it.
      expect(find.text('What this covers'), findsOneWidget);
    });

    testWidgets('a settled offer is shown as an outcome, not as a question', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        inspections: FakeInspectionRepository(
          requests: <InspectionRequest>[
            _claimed(
              inspectorNet: 200,
              agreedTotal: 249,
              bidStatus: BidStatus.agreed,
            ),
          ],
        ),
        bids: FakeBidRepository()
          ..seed('req-1', net: 200, status: BidStatus.agreed),
        child: const RequestDetailPage(id: 'req-1'),
      );

      expect(find.text('Accept'), findsNothing);
      expect(find.text('Agreed'), findsOneWidget);
      // A settled total is a sum, not a shape: 249 the two sides agreed on plus the
      // 300 the centre charges. Printing "249 ر.س + centre fee" here would name the
      // centre's fee as a line above and then refuse to add it.
      expect(find.text('549 ر.س'), findsOneWidget);
      expect(find.text('249 ر.س + centre fee'), findsNothing);
    });
  });

  group('the failure messages', () {
    testWidgets('a refused offer says what was wrong with it', (
      WidgetTester tester,
    ) async {
      final FakeBidRepository bids = FakeBidRepository()
        ..failure = const InspectionFailure(
          'That job belongs to another inspector.',
          reason: InspectionFailureReason.notTheAssignedInspector,
        );

      await _pump(
        tester,
        inspections: FakeInspectionRepository(
          requests: <InspectionRequest>[_claimed()],
        ),
        bids: bids,
        child: const InspectorJobDetailPage(id: 'req-1'),
      );

      await tester.tap(find.text('Offer a different amount'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '200');
      await tester.tap(find.text('Send offer'));
      await tester.pumpAndSettle();

      // The specific sentence, not the generic banner. An inspector who lost a claim
      // race and is told "try again" will try again forever.
      expect(
        find.text('This job belongs to another inspector.'),
        findsOneWidget,
      );
      // And the sheet stays open, so the figure they typed is still there.
      expect(find.text('Send offer'), findsOneWidget);
    });

    testWidgets('a refused answer says so too', (WidgetTester tester) async {
      final FakeInspectionRepository inspections =
          FakeInspectionRepository(
              requests: <InspectionRequest>[_claimed()],
              // Only the answer fails. Letting the read fail too would render the
              // page's load error, and the test would "pass" on a banner that had
              // nothing to do with the answer being refused.
            )
            ..respondFailure = const InspectionFailure(
              'That offer is no longer open.',
              reason: InspectionFailureReason.noOfferToRespondTo,
            );

      await _pump(
        tester,
        inspections: inspections,
        bids: FakeBidRepository()..seed('req-1', net: 200),
        child: const RequestDetailPage(id: 'req-1'),
      );

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ok');
      await tester.tap(find.text('Accept').last);
      await tester.pumpAndSettle();

      // The ARB sentence for this reason, not the repository's English log line —
      // which is what makes the panel read in the buyer's language.
      expect(find.text('That offer is no longer open.'), findsOneWidget);
      // And the card survives the refusal, because the offer has not gone anywhere:
      // the buyer's answer was never recorded, so the question is still open.
      expect(find.text('Accept'), findsOneWidget);
    });
  });

  group('the widget', () {
    testWidgets('the sheet is not a Material form sheet', (
      WidgetTester tester,
    ) async {
      // A bottom sheet with a text field in it has to lift above the keyboard, or
      // two thirds of it is covered and the send button is unreachable.
      await _pump(
        tester,
        inspections: FakeInspectionRepository(
          requests: <InspectionRequest>[_claimed()],
        ),
        bids: FakeBidRepository(),
        child: const InspectorJobDetailPage(id: 'req-1'),
      );

      await tester.tap(find.text('Offer a different amount'));
      await tester.pumpAndSettle();

      expect(find.byType(DesignTextField), findsNWidgets(2));
      expect(find.byType(BottomSheet), findsOneWidget);
      // The note field is optional and says so, because an inspector explaining
      // themselves under time pressure is not going to read a required marker and
      // decide to skip it.
      expect(find.text('Note for the buyer (optional)'), findsOneWidget);
    });
  });
}
