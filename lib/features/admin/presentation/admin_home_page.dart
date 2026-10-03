import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/admin_controller.dart';
import '../data/admin_repository.dart';
import 'admin_accounts_tab.dart';
import 'admin_failure_localizations.dart';
import 'admin_finance_tab.dart';
import 'admin_orders_tab.dart';
import 'admin_settings_tab.dart';
import 'admin_verification_tab.dart';

/// The admin panel: one screen, five tabs.
///
/// Five tabs and not five routes. The sections share a session, an outbox and a set of
/// cross-cutting facts — approving an inspector changes the accounts list, and the
/// suspension toggle moves a row between this panel and the job board — so a route
/// per section would mean re-deciding the auth and access rules five times over, in
/// five files, and the router would grow a redirect per section instead of one.
///
/// A [TabBar] rather than [AppBottomNav]. The design's bottom bar is three items with
/// short labels for the two primary journeys; five Arabic labels will not fit a
/// phone's bottom edge, and a tab strip that scrolls is the platform's own answer to
/// "more sections than fit".
class AdminHomePage extends ConsumerWidget {
  const AdminHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // Watched rather than read: a failed write leaves an error in this state, and the
    // banner below is the only place it is shown. The whole panel listening for it is
    // deliberate — a failure in one section is a fact about the admin's session, not
    // about the tab that happened to be open.
    final AsyncValue<void> writes = ref.watch(adminControllerProvider);
    final Object? failure = writes.error;

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.adminTitle),
          // A scrollable strip so the fifth tab is reachable on a narrow phone
          // without the bar trying to fit all five labels on one line.
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Widget>[
              Tab(text: l10n.adminTabVerification),
              Tab(text: l10n.adminTabAccounts),
              Tab(text: l10n.adminTabFinance),
              Tab(text: l10n.adminTabOrders),
              Tab(text: l10n.adminTabSettings),
            ],
          ),
        ),
        body: Column(
          children: <Widget>[
            if (failure != null)
              _WriteFailureBanner(
                onDismissed: () =>
                    ref.read(adminControllerProvider.notifier).clearError(),
              ),
            Expanded(
              child: TabBarView(
                children: const <Widget>[
                  AdminVerificationTab(),
                  AdminAccountsTab(),
                  AdminFinanceTab(),
                  AdminOrdersTab(),
                  AdminSettingsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The banner for a write that failed.
///
/// A banner across the whole panel rather than a message inside the tab that failed,
/// because the failure arrives after the tab has usually been left: an admin approves
/// the last inspector in the queue and taps straight through to the accounts tab, and
/// the accounts tab has no idea anything went wrong. One shared place to look is
/// kinder than making the admin remember which button they pressed.
class _WriteFailureBanner extends ConsumerWidget {
  const _WriteFailureBanner({required this.onDismissed});

  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Object? failure = ref.watch(adminControllerProvider).error;
    if (failure == null) return const SizedBox.shrink();

    final String message = switch (failure) {
      final AdminFailure adminFailure => adminFailure.localizedMessage(context),
      // Deliberately not the raw error. An unexpected exception can carry a
      // Supabase message written for developers; the detail went to the log.
      final Object _ => l10n.errorGeneric,
    };

    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.error_outline,
              size: 20,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: onDismissed,
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}