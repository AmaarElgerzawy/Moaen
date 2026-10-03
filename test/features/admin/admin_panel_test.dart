import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moaen/core/localization/locale_provider.dart';
import 'package:moaen/core/pricing/commission.dart';
import 'package:moaen/core/pricing/commission_controller.dart';
import 'package:moaen/core/theme/app_theme.dart';
import 'package:moaen/features/admin/application/admin_controller.dart';
import 'package:moaen/features/admin/data/admin_repository.dart';
import 'package:moaen/features/admin/domain/financial_overview.dart';
import 'package:moaen/features/admin/domain/order_summary.dart';
import 'package:moaen/features/admin/presentation/admin_accounts_tab.dart';
import 'package:moaen/features/admin/presentation/admin_finance_tab.dart';
import 'package:moaen/features/admin/presentation/admin_home_page.dart';
import 'package:moaen/features/admin/presentation/admin_orders_tab.dart';
import 'package:moaen/features/admin/presentation/admin_settings_tab.dart';
import 'package:moaen/features/admin/presentation/admin_verification_tab.dart';
import 'package:moaen/features/auth/auth_controller.dart';
import 'package:moaen/features/auth/user_profile.dart';
import 'package:moaen/features/cities/application/city_controller.dart';
import 'package:moaen/features/inspections/application/inspection_controller.dart';
import 'package:moaen/features/inspections/domain/inspection_centre.dart';
import 'package:moaen/features/inspections/domain/inspection_request.dart';
import 'package:moaen/l10n/gen/app_localizations.dart';

import '../../support/fake_admin_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_cities.dart';
import '../../support/fake_inspection_repository.dart';

/// The admin panel's five tabs, driven through the real providers.
///
/// Each tab gets its own file in `lib/`, and each one can be wrong in isolation — a
/// queue that approves the wrong account, a suspension toggle wired to the wrong
/// column, a commission form that saves a percentage as a flat amount. So these tests
/// assert on the *write that left the screen*, not on the widget tree: a panel that
/// renders correctly and sends the wrong update is the failure a screenshot review
/// cannot catch.
const UserProfile _admin = UserProfile(
  id: 'admin-1',
  fullName: 'Operations',
  email: 'ops@moaen.test',
  role: UserRole.admin,
  locationCity: 'Riyadh',
);

class _AdminAuth extends AuthController {
  @override
  Future<UserProfile?> build() async => _admin;
}

/// Pumps [child] with the admin's repositories in place.
///
/// [child] goes inside a [Scaffold] because the tabs are body content, not pages:
/// [AdminHomePage] is the page that supplies one, and a bare `TextField` in the
/// accounts tab's search row has no `Material` ancestor without it.
///
/// On a tall surface, for the same reason every other panel test in this suite is: the
/// tabs are `ListView`s several times the default 800x600 viewport, and a card at the
/// foot of one is not in the tree rather than merely off screen.
Future<void> _pump(
  WidgetTester tester, {
  required FakeAdminRepository admin,
  FakeCommissionRepository? commission,
  FakeInspectionRepository? inspections,
  FakeIdentityRepository? identity,
  required Widget child,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1000, 3000);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminRepositoryProvider.overrideWithValue(admin),
        commissionRepositoryProvider.overrideWithValue(
          commission ?? FakeCommissionRepository(),
        ),
        identityRepositoryProvider.overrideWithValue(
          identity ?? FakeIdentityRepository(),
        ),
        inspectionRepositoryProvider.overrideWithValue(
          inspections ?? FakeInspectionRepository(),
        ),
        authControllerProvider.overrideWith(_AdminAuth.new),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(profile: _admin, userId: _admin.id),
        ),
        localeProvider.overrideWithValue(const Locale('en')),
        citiesProvider.overrideWith((Ref ref) async => testCities),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('AdminHomePage', () {
    testWidgets('is five sections, and one failed write outlives the tab', (
      WidgetTester tester,
    ) async {
      // A failure in one section is a fact about the admin's *session*, not about the
      // tab that happened to be open: an admin approves the last inspector and taps
      // straight through to Finance. The banner sits above the tab strip for exactly
      // that reason, so this asserts it is still on screen after the switch.
      final FakeAdminRepository admin = FakeAdminRepository(
        users: <UserProfile>[
          buildUser(id: 'i-1', name: 'Karim Adel'),
          buildUser(id: 'i-2', name: 'Nadia Hassan'),
        ],
      );

      await _pump(tester, admin: admin, child: const AdminHomePage());

      for (final String tab in <String>[
        'Verification',
        'Accounts',
        'Finance',
        'Orders',
        'Settings',
      ]) {
        expect(find.text(tab), findsOneWidget);
      }

      await tester.tap(find.text('Approve').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve').last);
      await tester.pumpAndSettle();

      // The next approval is refused — which is what an RLS denial or a dropped
      // connection looks like from inside the app.
      admin.failure = const AdminFailure(
        'Only an administrator can do that.',
        reason: AdminFailureReason.notAnAdmin,
      );
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Finance'));
      await tester.pumpAndSettle();

      // The ARB sentence, not the repository's English log line.
      expect(find.text('Only an administrator can do that.'), findsOneWidget);
    });
  });

  group('the verification queue', () {
    testWidgets('lists only the inspectors awaiting a decision', (
      WidgetTester tester,
    ) async {
      // The tab's whole reason for existing: "who do I owe an answer to", not "what
      // exists". An approved inspector in this list is an admin re-reading a card they
      // have already decided.
      final FakeAdminRepository admin = FakeAdminRepository(
        users: <UserProfile>[
          buildUser(id: 'i-1', name: 'Karim Adel'),
          buildUser(id: 'i-2', name: 'Nadia Hassan', approved: true),
          buildUser(id: 'c-1', name: 'Buyer One', role: UserRole.client),
        ],
      );

      await _pump(tester, admin: admin, child: const AdminVerificationTab());

      expect(find.text('Karim Adel'), findsOneWidget);
      expect(find.text('Nadia Hassan'), findsNothing);
      // A buyer is approved at sign-up and is never reviewed, so it is not in this
      // queue under either the role filter or the approval flag.
      expect(find.text('Buyer One'), findsNothing);
    });

    testWidgets('names the account with no document rather than hiding it', (
      WidgetTester tester,
    ) async {
      // Migration 0011's grandfathering produces exactly this row, and the queue has
      // to be able to act on it: an admin who cannot see the account cannot approve
      // around the missing photograph.
      await _pump(
        tester,
        admin: FakeAdminRepository(
          users: <UserProfile>[
            buildUser(id: 'i-1', name: 'Karim Adel', idPhoto: ''),
          ],
        ),
        child: const AdminVerificationTab(),
      );

      expect(find.text('No ID photo on file'), findsWidgets);
      // The decision is still available, because refusing to show a row is not a way to
      // resolve a missing file.
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
    });

    testWidgets('says how many approval emails are unsent', (
      WidgetTester tester,
    ) async {
      // The honest answer to "did those inspectors get told". A count, not a promise,
      // because the edge function that drains the outbox may not be deployed at all.
      await _pump(
        tester,
        admin: FakeAdminRepository(),
        child: const AdminVerificationTab(),
      );

      expect(find.text('2 notifications not sent yet'), findsOneWidget);
    });

    testWidgets('approving confirms first, then writes once', (
      WidgetTester tester,
    ) async {
      final FakeAdminRepository admin = FakeAdminRepository(
        users: <UserProfile>[buildUser(id: 'i-1', name: 'Karim Adel')],
      );

      await _pump(tester, admin: admin, child: const AdminVerificationTab());

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      // The confirmation names the person and says what happens next — an approval
      // that sends an email is not something to do by accident.
      expect(find.text('Approve Karim Adel?'), findsOneWidget);
      expect(find.text('They will be emailed once approved.'), findsOneWidget);

      // Backing out writes nothing.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(admin.writes, isEmpty);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve').last);
      await tester.pumpAndSettle();

      expect(admin.writes, <({String id, String method, Object? value})>[
        (method: 'approve', id: 'i-1', value: null),
      ]);
      // And the row leaves the queue, because the queue is the working list.
      expect(find.text('Karim Adel'), findsNothing);
      expect(
        find.text('No inspectors are waiting for review.'),
        findsOneWidget,
      );
    });

    testWidgets('rejecting needs a reason before the button will send', (
      WidgetTester tester,
    ) async {
      // The inspector is the one who reads it, so an account refused with no
      // explanation generates a support message per rejection. The rule is visible
      // before the tap rather than as an error after it.
      final FakeAdminRepository admin = FakeAdminRepository(
        users: <UserProfile>[buildUser(id: 'i-1', name: 'Karim Adel')],
      );

      await _pump(tester, admin: admin, child: const AdminVerificationTab());

      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      expect(
        find.text('Why are you rejecting this inspector?'),
        findsOneWidget,
      );

      final Finder confirm = find.widgetWithText(FilledButton, 'Reject');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'The ID is unreadable.');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reject').last);
      await tester.pumpAndSettle();

      expect(admin.writes, <({String id, String method, Object? value})>[
        (method: 'reject', id: 'i-1', value: 'The ID is unreadable.'),
      ]);
      // The reason is kept on the profile, so the next admin to look sees why the
      // account was refused rather than finding an unexplained refusal.
      expect(admin.users.single.rejectionReason, 'The ID is unreadable.');
    });

    testWidgets('a whitespace reason never reaches the repository', (
      WidgetTester tester,
    ) async {
      // The dialog disables its button, so the only way to reach the guard is a caller
      // that skips the dialog — a keyboard shortcut, or a future refactor. The guard
      // is the repository's own, and it refuses on the *trimmed* value, so a run of
      // spaces counts as no reason at all.
      final FakeAdminRepository admin = FakeAdminRepository(
        users: <UserProfile>[buildUser(id: 'i-1', name: 'Karim Adel')],
      );

      await expectLater(
        admin.reject('i-1', '   '),
        throwsA(
          isA<AdminFailure>().having(
            (AdminFailure f) => f.reason,
            'reason',
            AdminFailureReason.rejectionReasonRequired,
          ),
        ),
      );
      // Recorded after the guard, so a refused rejection leaves no trace on the
      // profile for the next admin to read.
      expect(admin.writes, isEmpty);
      expect(admin.users.single.rejectionReason, isNull);
    });
  });

  group('the accounts tab', () {
    testWidgets('suspends a buyer and restores the same account', (
      WidgetTester tester,
    ) async {
      // Buyers are suspendable too — the requirement is not inspectors-only, and the
      // buyer is who a fraud complaint is actually about.
      final FakeAdminRepository admin = FakeAdminRepository(
        users: <UserProfile>[
          buildUser(
            id: 'c-1',
            name: 'Nadia Hassan',
            role: UserRole.client,
            approved: true,
          ),
        ],
      );

      await _pump(tester, admin: admin, child: const AdminAccountsTab());

      // A client is provisioned approved without review, so no verification badge —
      // printing one would state something that did not happen.
      expect(find.text('Verified'), findsNothing);
      expect(find.text('Suspended'), findsNothing);

      await tester.tap(find.text('Suspend'));
      await tester.pumpAndSettle();

      expect(find.text('Suspend Nadia Hassan?'), findsOneWidget);
      // The consequence is spelled out, including what does *not* happen: jobs the
      // account already holds are not cancelled, so an admin does not have to choose
      // between undoing fraud and honouring a booking.
      expect(
        find.textContaining('Jobs they already hold are not cancelled.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Suspend').last);
      await tester.pumpAndSettle();

      expect(admin.writes, <({String id, String method, Object? value})>[
        (method: 'block', id: 'c-1', value: ''),
      ]);
      // Suspended rows stay on screen, badge and all — the screen exists to find the
      // account that was suspended and reverse it.
      expect(find.text('Suspended'), findsOneWidget);
      expect(find.text('Restore'), findsOneWidget);

      // Restoring is the safe direction, so it asks nothing: a dialog here would be a
      // second decision where the screen has already made one.
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();

      expect(admin.writes.last, (method: 'unblock', id: 'c-1', value: null));
      expect(find.text('Suspended'), findsNothing);
    });

    testWidgets('searches by name or email, case-insensitively', (
      WidgetTester tester,
    ) async {
      final FakeAdminRepository admin = FakeAdminRepository(
        users: <UserProfile>[
          buildUser(id: 'i-1', name: 'Karim Adel', email: 'karim@example.com'),
          buildUser(
            id: 'i-2',
            name: 'Nadia Hassan',
            email: 'nadia@example.com',
          ),
        ],
      );

      await _pump(tester, admin: admin, child: const AdminAccountsTab());

      await tester.enterText(find.byType(TextField).first, 'NADIA');
      await tester.pumpAndSettle();

      expect(find.text('Nadia Hassan'), findsOneWidget);
      expect(find.text('Karim Adel'), findsNothing);
    });

    testWidgets('shows a verified inspector with the date it was verified', (
      WidgetTester tester,
    ) async {
      // The date is the evidence. A badge reading "Verified" with no date does not tell
      // an admin whether this account was checked last week or in 2024.
      await _pump(
        tester,
        admin: FakeAdminRepository(
          users: <UserProfile>[
            buildUser(
              id: 'i-1',
              name: 'Karim Adel',
              approved: true,
            ).copyWith(approvedAt: DateTime.utc(2026, 3, 1)),
          ],
        ),
        child: const AdminAccountsTab(),
      );

      expect(find.text('Verified'), findsOneWidget);
      expect(find.textContaining('Verified 1 March 2026'), findsOneWidget);
    });

    testWidgets('suspends a repair centre as well as an account', (
      WidgetTester tester,
    ) async {
      // Centres are the third thing the panel can take out of service, and the only
      // one with no account behind it — so the toggle has to exist somewhere other
      // than the account list.
      final FakeAdminRepository admin = FakeAdminRepository(
        centres: <InspectionCentre>[
          buildCentre(id: 'c-1', name: 'Kartek Centre'),
        ],
      );

      await _pump(tester, admin: admin, child: const AdminAccountsTab());

      await tester.tap(find.text('Repair centres'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suspend'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suspend').last);
      await tester.pumpAndSettle();

      expect(admin.writes, <({String id, String method, Object? value})>[
        (method: 'blockCentre', id: 'c-1', value: null),
      ]);
      expect(find.text('Restore'), findsOneWidget);
    });
  });

  group('the finance tab', () {
    testWidgets('keeps the revenue, the escrow and the refunds apart', (
      WidgetTester tester,
    ) async {
      // One "volume" number would describe nothing: the escrow is money the platform
      // is holding for somebody and has not earned, and adding it to revenue would
      // overstate both.
      await _pump(
        tester,
        admin: FakeAdminRepository(
          money: const FinancialOverview(
            collectedVolume: 9800,
            platformRevenue: 476,
            heldInEscrow: 1200,
            refunded: 150,
            completedPayments: 7,
            totalPayments: 9,
          ),
        ),
        child: const AdminFinanceTab(),
      );

      expect(find.text('Platform revenue'), findsOneWidget);
      expect(find.text('476 ر.س'), findsOneWidget);
      expect(find.text('4.9% of what was collected'), findsOneWidget);
      expect(find.text('7 payments'), findsOneWidget);

      expect(find.text('Collected payments'), findsOneWidget);
      expect(find.text('9,800 ر.س'), findsOneWidget);
      expect(find.text('Held in escrow'), findsOneWidget);
      expect(find.text('1,200 ر.س'), findsOneWidget);
      expect(find.text('Refunded'), findsOneWidget);
      expect(find.text('150 ر.س'), findsOneWidget);
    });

    testWidgets('says so when nothing has settled', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        admin: FakeAdminRepository(),
        child: const AdminFinanceTab(),
      );

      expect(find.text('No payments have been settled yet.'), findsOneWidget);
    });
  });

  group('the orders tab', () {
    testWidgets('shows the status breakdown from the grouped read', (
      WidgetTester tester,
    ) async {
      // Grouped in the database rather than counted from the page, so the counts
      // cannot drift from the rows — and so the breakdown survives the filters, which
      // a count computed from the filtered page would not.
      await _pump(
        tester,
        admin: FakeAdminRepository(
          summary: const <OrderSummary>[
            OrderSummary(status: 'pending', orders: 4, value: 2000),
            OrderSummary(status: 'inProgress', orders: 2, value: 1100),
          ],
        ),
        inspections: FakeInspectionRepository(
          requests: <InspectionRequest>[
            buildRequest(
              id: 'r-1',
              referenceNo: 1001,
              status: InspectionStatus.accepted,
              inspectorId: 'i-1',
            ),
          ],
        ),
        child: const AdminOrdersTab(),
      );

      expect(find.text('4 orders · 2,000 ر.س'), findsOneWidget);
      expect(find.text('2 orders · 1,100 ر.س'), findsOneWidget);
      // The raw status name, because this build may not have copy for every status a
      // future migration adds, and a blank cell would hide the row an admin most needs.
      expect(find.text('pending'), findsOneWidget);
      expect(find.text('inProgress'), findsOneWidget);
    });

    testWidgets('cancels an open order after a confirmation', (
      WidgetTester tester,
    ) async {
      // The monitor is the one place an admin can take work off the platform, so the
      // write is the thing under test — with a finished order offering no button at
      // all, because `enforce_inspection_transition` would refuse it.
      final FakeInspectionRepository inspections = FakeInspectionRepository(
        requests: <InspectionRequest>[
          buildRequest(id: 'r-1', referenceNo: 1001),
          buildRequest(
            id: 'r-2',
            referenceNo: 1002,
            status: InspectionStatus.completed,
          ),
        ],
      );

      await _pump(
        tester,
        admin: FakeAdminRepository(),
        inspections: inspections,
        child: const AdminOrdersTab(),
      );

      // One button for the two orders: the completed one offers nothing, because
      // `enforce_inspection_transition` would refuse the write and a button that
      // fails is worse than no button.
      expect(find.text('Cancel this order'), findsOneWidget);

      await tester.tap(find.text('Cancel this order'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel order MN-1001?'), findsOneWidget);
      // Backing out takes the order off nobody.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(inspections.cancelledIds, isEmpty);

      await tester.tap(find.text('Cancel this order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel this order').last);
      await tester.pumpAndSettle();

      expect(inspections.cancelledIds, <String>['r-1']);
      // And the cancelled order stops offering the button too, so the monitor cannot
      // ask the same question twice.
      expect(find.text('Cancel this order'), findsNothing);
    });
  });

  group('the settings tab', () {
    testWidgets('a percentage reads as a percentage', (
      WidgetTester tester,
    ) async {
      // The whole reason there are two controls rather than one: 10 is a flat 10 SAR
      // under "fixed" and a 10% cut under "percentage", and an admin who types a
      // percentage while the type still reads "fixed" has set something else
      // entirely. So the worked example follows the type.
      await _pump(
        tester,
        admin: FakeAdminRepository(),
        child: const AdminSettingsTab(),
      );

      await tester.tap(find.text('Percentage'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '10');
      await tester.pumpAndSettle();

      expect(find.text('On a 500 SAR request'), findsOneWidget);
      expect(find.text('50 ر.س'), findsOneWidget);
      expect(find.text('450 ر.س'), findsOneWidget);
      expect(find.text('500 ر.س'), findsOneWidget);
    });

    testWidgets('saving a fixed amount sends a fixed commission', (
      WidgetTester tester,
    ) async {
      final FakeAdminRepository admin = FakeAdminRepository();

      await _pump(tester, admin: admin, child: const AdminSettingsTab());

      // The seeded 49, which is migration 0011's own default — the form opens on what
      // the database is actually charging rather than on a placeholder. Read off the
      // field's controller, because `find.text` matches rendered `Text` widgets and a
      // `TextField`'s contents is not one.
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        '49',
      );

      await tester.enterText(find.byType(TextField), '75');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(admin.writes.last, (
        method: 'setCommission',
        id: 'platform_settings',
        value: const Commission(type: CommissionType.fixed, value: 75),
      ));
      expect(find.text('Saved.'), findsOneWidget);
    });

    testWidgets('an out-of-range commission is refused and named', (
      WidgetTester tester,
    ) async {
      // 150% is not a commission, and the settings table says so. The refusal has to
      // reach the panel's own banner rather than the admin finding out on the next
      // priced request.
      final FakeAdminRepository admin = FakeAdminRepository();

      await _pump(tester, admin: admin, child: AdminHomePage());

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Percentage'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '150');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('That value is out of range.'), findsOneWidget);
      expect(
        admin.writes.where(
          (({String id, String method, Object? value}) w) =>
              w.method == 'setCommission',
        ),
        isEmpty,
      );
    });
  });
}
