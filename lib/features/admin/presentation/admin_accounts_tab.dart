import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/user_profile.dart';
import '../../auth/user_role_localizations.dart';
import '../../../core/format/saudi_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../inspections/domain/inspection_centre.dart';
import '../../inspections/presentation/widgets/design_widgets.dart';
import '../application/admin_controller.dart';

/// Every account, and every centre, with the switch that takes each out of service.
///
/// Two lists on one tab rather than two tabs, because the decision is the same in both
/// cases — "should this be offered to the platform right now" — and an admin
/// suspending a fraudulent shop while looking for the account that listed it is one
/// uninterrupted task. Splitting them would make it two navigations.
///
/// Suspended rows are shown, not hidden. The whole purpose of this screen is to find
/// the account that was suspended and reverse it.
class AdminAccountsTab extends ConsumerWidget {
  const AdminAccountsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<UserProfile>> accounts = ref.watch(
      adminUsersProvider,
    );
    final AsyncValue<List<InspectionCentre>> centres = ref.watch(
      adminCentresProvider,
    );

    return DefaultTabController(
      length: 2,
      child: Column(
        children: <Widget>[
          TabBar(
            tabs: <Widget>[
              Tab(text: l10n.adminTabAccounts),
              Tab(text: l10n.adminCentresTitle),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _AccountList(accounts: accounts),
                _CentreList(centres: centres),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountList extends ConsumerStatefulWidget {
  const _AccountList({required this.accounts});

  final AsyncValue<List<UserProfile>> accounts;

  @override
  ConsumerState<_AccountList> createState() => _AccountListState();
}

class _AccountListState extends ConsumerState<_AccountList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            0,
          ),
          child: TextField(
            onChanged: (String value) => setState(() => _query = value),
            // Left to the field's own bidi resolution: a search term may be an Arabic
            // name, an email address, or either with a Latin fragment, and forcing a
            // direction would put the caret somewhere the typist did not expect.
            textAlign: TextAlign.start,
            decoration: InputDecoration(
              labelText: l10n.adminSearchAccounts,
              prefixIcon: const Icon(Icons.search, size: 20),
            ),
          ),
        ),
        Expanded(
          child: switch (widget.accounts) {
            AsyncData<List<UserProfile>>(value: final List<UserProfile> rows) =>
              _rows(context, ref, l10n, _filter(rows, _query)),
            AsyncError<List<UserProfile>>() => DesignRetry(
              message: l10n.errorGeneric,
              actionLabel: l10n.actionRetry,
              onRetry: () => ref.invalidate(adminUsersProvider),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ],
    );
  }

  /// Name and email, case-insensitively.
  ///
  /// Arabic has no case, so `toLowerCase` is a no-op on half the app's users and a
  /// genuine convenience on the rest — which is exactly why the same one call is right
  /// for both rather than a helper per script.
  static List<UserProfile> _filter(List<UserProfile> rows, String query) {
    final String term = query.trim().toLowerCase();
    if (term.isEmpty) return rows;
    return rows
        .where(
          (UserProfile profile) =>
              profile.fullName.toLowerCase().contains(term) ||
              profile.email.toLowerCase().contains(term),
        )
        .toList();
  }

  Widget _rows(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    List<UserProfile> rows,
  ) {
    if (rows.isEmpty) return DesignEmpty(title: l10n.adminAccountsEmpty);

    final SaudiFormat format = SaudiFormat(
      Localizations.localeOf(context).toString(),
    );

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (BuildContext context, int index) {
        final UserProfile profile = rows[index];
        final DateTime? approvedAt = profile.approvedAt;

        return DesignCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  InitialAvatar(name: profile.fullName, diameter: 44),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          profile.fullName.isEmpty
                              ? profile.email
                              : profile.fullName,
                          style: AppText.title(15),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          profile.role.localizedName(context),
                          style: AppText.secondary(12),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(profile: profile),
                ],
              ),
              // Only for an inspector who has actually been verified. A client is
              // provisioned approved without ever having been reviewed, so printing a
              // verification date for one would be stating something that did not
              // happen.
              if (profile.role == UserRole.inspector &&
                  profile.isApproved &&
                  approvedAt != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.adminVerifiedOn(format.longDate(approvedAt.toLocal())),
                  style: AppText.secondary(12),
                ),
              ],
              if (profile.blockedReason case final String reason
                  when reason.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(reason, style: AppText.secondary(12)),
              ],
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: profile.isBlocked
                    ? OutlinedButton.icon(
                        onPressed: () => _restore(context, ref, profile),
                        icon: const Icon(Icons.lock_open, size: 18),
                        label: Text(l10n.adminRestore),
                      )
                    : FilledButton.icon(
                        onPressed: () => _suspend(context, ref, profile),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.live,
                        ),
                        icon: const Icon(Icons.pause, size: 18),
                        label: Text(l10n.adminSuspend),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _suspend(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => _SuspendDialog(
        title: l10n.adminSuspendConfirm(profile.fullName),
        prompt: l10n.adminSuspendReasonPrompt,
        notify: l10n.adminSuspendNotify,
        confirmLabel: l10n.adminSuspend,
      ),
    );
    if (reason == null) return;

    try {
      await ref
          .read(adminControllerProvider.notifier)
          .setBlocked(profile.id, blocked: true, reason: reason);
    } on Object {
      // The panel's banner owns the message; see the same catch in the
      // verification tab.
    }
  }

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
  ) async {
    // No confirmation. Restoring is the safe direction: it puts an account back into
    // service, and the only way to be wrong about it is to press it on the wrong row,
    // which the row's own badge already shows. A dialog here would be a second
    // decision where the screen has already made one.
    try {
      await ref
          .read(adminControllerProvider.notifier)
          .setBlocked(profile.id, blocked: false);
    } on Object {
      // See [_suspend].
    }
  }
}

class _CentreList extends ConsumerWidget {
  const _CentreList({required this.centres});

  final AsyncValue<List<InspectionCentre>> centres;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return switch (centres) {
      AsyncData<List<InspectionCentre>>(
        value: final List<InspectionCentre> rows,
      )
          when rows.isEmpty =>
        DesignEmpty(title: l10n.adminCentresEmpty),
      AsyncData<List<InspectionCentre>>(
        value: final List<InspectionCentre> rows,
      ) =>
        ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (BuildContext context, int index) {
            final InspectionCentre centre = rows[index];
            return DesignCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(centre.name, style: AppText.title(15)),
                            const SizedBox(height: AppSpacing.xs),
                            Text(centre.city, style: AppText.secondary(12)),
                          ],
                        ),
                      ),
                      if (centre.isBlocked)
                        AppPill(
                          label: l10n.adminBadgeSuspended,
                          tone: PillTone.warning,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Its own line rather than beside the name. The design's button
                  // theme sets `minimumSize: Size.fromHeight(...)`, whose width is
                  // `double.infinity`; inside a `Row` that is an unbounded width and
                  // the layout throws. An `Align` loosens the constraints so the
                  // button can take its own width — which is what the account rows
                  // above have always done, and the reason they work.
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: centre.isBlocked
                        ? OutlinedButton.icon(
                            onPressed: () =>
                                _toggle(context, ref, centre, false),
                            icon: const Icon(Icons.lock_open, size: 18),
                            label: Text(l10n.adminRestore),
                          )
                        : FilledButton.icon(
                            onPressed: () =>
                                _toggle(context, ref, centre, true),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.live,
                            ),
                            icon: const Icon(Icons.pause, size: 18),
                            label: Text(l10n.adminSuspend),
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      AsyncError<List<InspectionCentre>>() => DesignRetry(
        message: l10n.errorGeneric,
        actionLabel: l10n.actionRetry,
        onRetry: () => ref.invalidate(adminCentresProvider),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    InspectionCentre centre,
    bool blocked,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (blocked) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(l10n.adminSuspendConfirm(centre.name)),
          content: Text(l10n.adminCentreSuspendNotify),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.adminSuspend),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      await ref
          .read(adminControllerProvider.notifier)
          .setCentreBlocked(centre.id, blocked: blocked);
    } on Object {
      // The panel's banner owns the message.
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return switch ((profile.isBlocked, profile.isApproved, profile.role)) {
      (true, _, _) => AppPill(
        label: l10n.adminBadgeSuspended,
        tone: PillTone.warning,
      ),
      // A client is approved without ever being reviewed, so "verified" would
      // state something that did not happen — on *either* flag, which is why the
      // role is matched here rather than only for the unapproved client below.
      // Matching on the flag alone would leave every real buyer, who is approved
      // at sign-up, wearing a badge for a review nobody performed.
      (false, false, UserRole.inspector) => AppPill(
        label: l10n.adminBadgePending,
        tone: PillTone.neutral,
      ),
      (false, _, UserRole.client) => const SizedBox.shrink(),
      _ => AppPill(label: l10n.adminBadgeVerified, tone: PillTone.success),
    };
  }
}

/// The suspension dialog: a confirmation, a consequence and an optional reason.
///
/// The reason is optional because a suspension is often immediate and unexplained —
/// an account spamming the job board, a suspected fraud — and demanding a paragraph
/// before an admin can act would mean the paragraph gets written after the fact, for
/// the log rather than for the account. When one is given, it is what the account's
/// owner is shown, which is why the field says so.
class _SuspendDialog extends StatefulWidget {
  const _SuspendDialog({
    required this.title,
    required this.prompt,
    required this.notify,
    required this.confirmLabel,
  });

  final String title;
  final String prompt;
  final String notify;
  final String confirmLabel;

  @override
  State<_SuspendDialog> createState() => _SuspendDialogState();
}

class _SuspendDialogState extends State<_SuspendDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.notify),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _reason,
            minLines: 1,
            maxLines: 3,
            // An admin writes this in whichever language their account reads, so it
            // is left to the field's own bidi rather than forced to the panel's
            // direction — and the caret follows the text rather than the screen.
            textAlign: TextAlign.start,
            decoration: InputDecoration(labelText: widget.prompt),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
