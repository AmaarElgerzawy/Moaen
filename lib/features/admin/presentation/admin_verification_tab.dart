import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../auth/user_profile.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../inspections/presentation/widgets/design_widgets.dart';
import '../application/admin_controller.dart';

/// The inspector verification queue.
///
/// The working list, not the roster: an admin opens this tab to decide on the
/// accounts waiting for a decision, and an already-approved inspector does not need
/// one. The full roster is the accounts tab's job, and the two answer different
/// questions — "who do I owe an answer to" versus "what exists".
class AdminVerificationTab extends ConsumerWidget {
  const AdminVerificationTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<UserProfile>> queue = ref.watch(reviewQueueProvider);
    final AsyncValue<int> pendingMail = ref.watch(pendingNotificationsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(reviewQueueProvider);
        ref.invalidate(pendingNotificationsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          if (pendingMail.value case final int count)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: NoticeBox(
                titleIcon: Icons.outgoing_mail,
                child: Text(
                  l10n.adminNotificationsPending(count),
                  style: AppText.secondary(13),
                ),
              ),
            ),
          ..._queueRows(context, ref, l10n, queue),
        ],
      ),
    );
  }

  /// The list itself, so the build method reads as the page's shape rather than as a
  /// nested switch inside a children list.
  List<Widget> _queueRows(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    AsyncValue<List<UserProfile>> queue,
  ) => switch (queue) {
    AsyncData<List<UserProfile>>(value: final List<UserProfile> rows)
        when rows.isEmpty =>
      <Widget>[DesignEmpty(title: l10n.adminQueueEmpty)],
    AsyncData<List<UserProfile>>(value: final List<UserProfile> rows) => <Widget>[
      for (final UserProfile profile in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _ReviewCard(profile: profile),
        ),
    ],
    AsyncError<List<UserProfile>>() => <Widget>[
      DesignRetry(
        message: l10n.errorGeneric,
        actionLabel: l10n.actionRetry,
        onRetry: () => ref.invalidate(reviewQueueProvider),
      ),
    ],
    _ => const <Widget>[
      Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Center(child: CircularProgressIndicator()),
      ),
    ],
  };
}

/// One inspector, with the two decisions that can be made about them.
class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return DesignCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              InitialAvatar(name: profile.fullName),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      profile.fullName.isEmpty ? profile.email : profile.fullName,
                      style: AppText.title(15),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      // The email, not the city: an inspector with no service city
                      // chosen yet is a real state, and "الرياض" printed where a city
                      // should be would be a claim nobody made. The email is always
                      // there and is what an admin needs to answer a question about
                      // the account anyway.
                      profile.email,
                      style: AppText.secondary(12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              AppPill(
                label: profile.isAwaitingDocuments
                    ? l10n.adminNoDocument
                    : l10n.adminDocumentOnFile,
                icon: profile.isAwaitingDocuments
                    ? Icons.help_outline
                    : Icons.badge_outlined,
                tone: profile.isAwaitingDocuments
                    ? PillTone.warning
                    : PillTone.success,
              ),
              if (profile.isBlocked) ...<Widget>[
                const SizedBox(width: AppSpacing.xs),
                AppPill(
                  label: l10n.adminBadgeSuspended,
                  icon: Icons.pause_circle_outline,
                  tone: PillTone.warning,
                ),
              ],
            ],
          ),
          if (profile.rejectionReason case final String reason
              when reason.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            NoticeBox(
              titleIcon: Icons.block_outlined,
              child: Text(reason, style: AppText.secondary(13)),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _IdPhotoPreview(profile: profile),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _confirmApprove(context, ref),
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(l10n.adminApprove),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _promptReject(context, ref),
                  icon: const Icon(Icons.close, size: 18),
                  label: Text(l10n.adminReject),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmApprove(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.adminApproveConfirm(profile.fullName)),
        content: Text(l10n.adminApproveNotify),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.adminApprove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(adminControllerProvider.notifier).approve(profile.id);
    } on Object {
      // The panel's own banner owns the message. A snackbar here would say the same
      // sentence in a second place, and the banner is the one that survives the admin
      // tapping through to another tab.
      messenger.hideCurrentSnackBar();
    }
  }

  Future<void> _promptReject(BuildContext context, WidgetRef ref) async {
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _RejectDialog(profile: profile),
    );
    if (reason == null) return;

    try {
      await ref
          .read(adminControllerProvider.notifier)
          .reject(profile.id, reason);
    } on Object {
      // See [_confirmApprove]: the panel's banner is the single place a failed
      // administrative write is reported.
    }
  }
}

/// The rejection dialog: a prompt and a required reason.
///
/// The reason is required rather than optional because the inspector is the one who
/// reads it — an account refused with no explanation generates a support message, and
/// an admin has to answer each one individually. The confirm button stays disabled
/// until something has been typed, so the rule is visible before the tap rather than
/// as an error after it.
class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.profile});

  final UserProfile profile;

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool ready = _reason.text.trim().isNotEmpty;

    return AlertDialog(
      title: Text(l10n.adminRejectPrompt),
      content: TextField(
        controller: _reason,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        // An admin writes this in whichever language their inspector reads, so it is
        // left to the field's own bidi rather than forced to the panel's direction.
        textAlign: TextAlign.start,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: l10n.fieldBidNote,
          helperText: l10n.bidBuyerReasonHint,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: ready
              ? () => Navigator.of(context).pop(_reason.text.trim())
              : null,
          child: Text(l10n.adminReject),
        ),
      ],
    );
  }
}

/// The identity document, signed and shown.
///
/// A separate future rather than a synchronous field, because the URL is minted per
/// read and the queue is a list: signing every document on every rebuild would be a
/// storage request per card per frame. Cached per profile by the provider below, so
/// scrolling the queue back and forth re-uses the same token.
///
/// A missing photograph renders as the design's own missing-photo frame rather than
/// an error. It is a real state — an inspector who signed up while their upload was
/// still in flight, and one that migration 0011's grandfathering deliberately
/// produces — and an admin needs to see the row to be able to approve around it.
class _IdPhotoPreview extends ConsumerWidget {
  const _IdPhotoPreview({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? path = profile.idPhotoPath;
    if (path == null || path.isEmpty) {
      return _MissingFrame();
    }

    final AsyncValue<String> url = ref.watch(_signedIdPhotoProvider(
      (profile.id, path),
    ));
    return switch (url) {
      AsyncData<String>(value: final String value) when value.isNotEmpty =>
        _PhotoFrame(url: value),
      _ => const _MissingFrame(),
    };
  }
}

/// A signed URL for one document, keyed by the account and the path.
///
/// Keyed on the path as well as the id so a *replacement* upload mints a new token
/// rather than serving the stale one from a cache that only knows the account. A
/// cached URL for a document the inspector has since replaced is precisely the
/// failure a verification queue must not have.
final _signedIdPhotoProvider = FutureProvider.family<String, (String, String)>((
  Ref ref,
  (String, String) key,
) {
  ref.watch(authControllerProvider);
  return ref.read(identityRepositoryProvider).signedUrlFor(key.$1, key.$2);
});

class _PhotoFrame extends StatelessWidget {
  const _PhotoFrame({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return LtrRegion(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Image.network(
          url,
          height: 160,
          width: double.infinity,
          fit: BoxFit.contain,
          alignment: Alignment.topLeft,
          errorBuilder: (_, _, _) => const _MissingFrame(),
        ),
      ),
    );
  }
}

class _MissingFrame extends StatelessWidget {
  const _MissingFrame();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return DashedBorderBox(
      child: SizedBox(
        height: 96,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.image_not_supported_outlined, size: 24),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.adminNoDocument,
                style: AppText.secondary(12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}