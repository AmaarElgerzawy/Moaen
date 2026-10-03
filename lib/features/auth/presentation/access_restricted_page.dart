import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/media/photo_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../inspections/presentation/widgets/design_widgets.dart';
import '../auth_controller.dart';
import '../user_profile.dart';

/// The screen an account lands on when it cannot use the platform yet.
///
/// Four states, one screen, because they share everything except two sentences: an
/// inspector waiting for review, an inspector turned down, a suspended account, and
/// an inspector who has never uploaded a document. A screen per state would repeat
/// the sign-out button and the empty-state header four times, and the differences
/// are not big enough to be worth that.
///
/// ## Why this is a route rather than a branch inside each screen
///
/// The alternative — letting every screen test [UserProfile.canOperate] and render
/// something else — puts the same rule in nine places, and the ninth is the one that
/// gets forgotten. The router resolves it once; see the redirect in `app_router`.
class AccessRestrictedPage extends ConsumerWidget {
  const AccessRestrictedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<UserProfile?> auth = ref.watch(authControllerProvider);
    final UserProfile? profile = auth.value;

    // The router only sends a signed-in account here, so a null profile is a
    // momentary race rather than a real state. The spinner is the honest answer:
    // rendering "suspended" for a profile that has not loaded yet is a lie told for
    // one frame, on a screen whose entire job is to be accurate about the account.
    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final AccessBlock block = profile.accessBlock;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appName),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.actionSignOut,
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: <Widget>[
              _StatusHeader(block: block),
              const SizedBox(height: AppSpacing.md),
              Text(
                _bodyFor(l10n, block, profile),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (_canUpload(block, profile)) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                NoticeBox(
                  title: l10n.accessDocumentsTitle,
                  titleIcon: Icons.badge_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.accessDocumentsBody,
                        style: AppText.secondary(13),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const _IdPhotoControl(),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              OutlinedButton.icon(
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).signOut(),
                icon: const Icon(Icons.logout, size: 18),
                label: Text(l10n.actionSignOut),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Whether an upload control belongs on this screen.
  ///
  /// True for an inspector who is waiting or was turned down: the document is the
  /// thing being reviewed, so replacing it is the only action that could change
  /// their state. False for a suspension, where the blocker is the account rather
  /// than the paperwork — an upload control there would be an invitation to keep
  /// trying, and a second thing to fail while the real blocker goes unaddressed.
  static bool _canUpload(AccessBlock block, UserProfile profile) =>
      profile.role == UserRole.inspector &&
      block != AccessBlock.suspended &&
      profile.isAwaitingDocuments;
}

/// The badge and the headline, which pair an icon with a phrase.
class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.block});

  final AccessBlock block;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // Awaiting approval is the one state that is *normal* rather than wrong: the
    // inspector did everything asked of them and the delay is the platform's. It
    // gets the neutral pill; only rejection and suspension get the warning tone.
    final bool isProblem = block != AccessBlock.awaitingApproval;

    return Row(
      children: <Widget>[
        AppPill(
          label: switch (block) {
            AccessBlock.awaitingApproval => l10n.adminBadgePending,
            AccessBlock.rejected => l10n.adminBadgeRejected,
            AccessBlock.suspended => l10n.adminBadgeSuspended,
            AccessBlock.none => l10n.adminBadgeVerified,
          },
          tone: isProblem ? PillTone.warning : PillTone.neutral,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(switch (block) {
            AccessBlock.awaitingApproval => l10n.accessAwaitingApprovalTitle,
            AccessBlock.rejected => l10n.accessRejectedTitle,
            AccessBlock.suspended => l10n.accessBlockedTitle,
            AccessBlock.none => l10n.appName,
          }, style: Theme.of(context).textTheme.headlineSmall),
        ),
      ],
    );
  }
}

String _bodyFor(
  AppLocalizations l10n,
  AccessBlock block,
  UserProfile profile,
) => switch (block) {
  AccessBlock.awaitingApproval => l10n.accessAwaitingApprovalBody,
  // The reason is an admin's free text, so it can be anything including an
  // empty string. The title is the honest fallback: "not approved" is true even
  // when no reason was recorded.
  AccessBlock.rejected => l10n.accessRejectedBody(
    profile.rejectionReason ?? l10n.accessRejectedTitle,
  ),
  AccessBlock.suspended => l10n.accessBlockedBody,
  // Unreachable: the router sends only a restricted account here. Falling back
  // to the awaiting-approval text rather than an empty string means a state
  // added to `AccessBlock` later shows something rather than a blank card.
  AccessBlock.none => l10n.accessAwaitingApprovalBody,
};

/// The upload control, plus whatever went wrong last time.
///
/// A leaf stateful widget rather than state on the page above, because the page is a
/// `ConsumerWidget` that rebuilds whenever the profile changes — and holding a picker
/// result across a rebuild belongs to whoever owns the button.
class _IdPhotoControl extends ConsumerStatefulWidget {
  const _IdPhotoControl();

  @override
  ConsumerState<_IdPhotoControl> createState() => _IdPhotoControlState();
}

class _IdPhotoControlState extends ConsumerState<_IdPhotoControl> {
  bool _busy = false;

  /// True after a failed attempt, which relabels the button.
  ///
  /// A message instead? The paragraph directly above the control already explains
  /// that the document is missing, and a banner saying "that failed" under a control
  /// that visibly changed its own label is the same fact stated twice. Relabelling
  /// also keeps the failure attached to the action that caused it, which is the one
  /// thing a first-time user is looking for.
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    if (_busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return ElevatedButton.icon(
      onPressed: _pick,
      icon: Icon(_failed ? Icons.refresh : Icons.upload_file, size: 18),
      label: Text(_failed ? l10n.actionRetryUpload : l10n.actionUploadId),
    );
  }

  Future<void> _pick() async {
    final PhotoPicker picker = ref.read(identityPhotoPickerProvider);
    final XFile? file = await _ask(picker);
    if (file == null || !mounted) return;

    setState(() => _busy = true);
    final bool uploaded = await ref
        .read(authControllerProvider.notifier)
        .updateIdPhoto(file);
    if (!mounted) return;

    // On success the profile now has a document, so `AccessRestrictedPage` stops
    // rendering this control and the branch below never gets a chance to show
    // "retry". Setting `_failed = false` anyway keeps the state honest if the
    // control is ever shown again with the same widget state.
    setState(() {
      _busy = false;
      _failed = !uploaded;
    });
  }

  /// The gallery, or null if it could not be opened *or* was dismissed.
  ///
  /// Both failures collapse into one answer on purpose, and neither is a null file:
  /// a platform channel that throws — the plugin unregistered, a permission refused —
  /// has not chosen a picture, so there is nothing to upload, and letting the
  /// exception escape would tear down the only screen an unapproved inspector can
  /// reach. That is the screen they would then need in order to recover from it.
  ///
  /// A dismissal is not a failure either, and the distinction is kept by *not*
  /// setting `_failed` here: a user who backs out of the gallery changed their mind,
  /// and relabelling the button "Try again" for that would report a problem they did
  /// not have. The picker throwing is the case that does relabel, because the caller
  /// cannot tell the two apart from the return value alone.
  Future<XFile?> _ask(PhotoPicker picker) async {
    try {
      return await picker.pickFromGallery();
    } on Object catch (error, stackTrace) {
      AppLogger.instance.error(
        'identity photo picker failed',
        error,
        stackTrace,
      );
      if (!mounted) return null;
      setState(() => _failed = true);
      return null;
    }
  }
}
