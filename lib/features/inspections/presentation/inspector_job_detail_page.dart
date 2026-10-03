import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/inspection_controller.dart';
import '../data/inspection_repository.dart';
import '../domain/inspection_request.dart';
import 'accept_request.dart';
import 'offer_widgets.dart';
import 'request_detail_page.dart' show StatusPill;
import 'widgets/design_widgets.dart';

/// One request as the inspector sees it, with the status transition actions.
///
/// A pushed screen the reference does not draw, so it is built from the design
/// system for the reason the buyer's equivalent page is: a Material `AppBar` in
/// an app that has none anywhere else would be the one place the design's own
/// language stops.
///
/// The action offered is decided entirely by the request's current status, and
/// the switch over [InspectionStatus] is exhaustive — adding a status to the
/// enum forces this page to decide what an inspector may do at that point
/// rather than defaulting silently. The transitions themselves are enforced by
/// the `enforce_inspection_transition` trigger, so a page that is somehow wrong
/// cannot move a request illegally; what the page has to get right is which
/// action to *offer*, and what to tell the inspector when they lose a claim
/// race.
class InspectorJobDetailPage extends ConsumerWidget {
  const InspectorJobDetailPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<void> action = ref.watch(
      inspectionRequestControllerProvider,
    );
    final AsyncValue<InspectionRequest> job = ref.watch(inspectorJobProvider(id));

    return Scaffold(
      body: Column(
        children: <Widget>[
          ShellHeader(
            title: l10n.actionViewDetails,
            trailing: job.value == null
                ? null
                : StatusPill(status: job.value!.status),
          ),
          Expanded(
            child: job.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: DesignRetry(
                  message: l10n.tabLoadError,
                  actionLabel: l10n.actionRetry,
                  onRetry: () => ref.invalidate(inspectorJobProvider(id)),
                ),
              ),
              data: (InspectionRequest request) {
                final String? stateNote = switch (request.status) {
                  InspectionStatus.pending => l10n.inspectorAvailableNote,
                  InspectionStatus.accepted ||
                  InspectionStatus.inProgress => l10n.inspectorAssignedNote,
                  InspectionStatus.completed ||
                  InspectionStatus.cancelled => null,
                };

                return ListView(
                  padding: const EdgeInsets.all(AppSpacing.inset),
                  children: <Widget>[
                    Text(request.reference, style: AppText.title(20)),
                    if (stateNote case final String note) ...<Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      Text(note, style: AppText.secondary(12)),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    TitledCard(
                      title: l10n.cardCarTitle,
                      child: Column(
                        children: <Widget>[
                          AccountRow(
                            label: l10n.fieldCarMake,
                            value: request.carMake,
                          ),
                          const DashedDivider(indent: AppSpacing.sm),
                          AccountRow(
                            label: l10n.fieldCarModel,
                            value: request.carModel,
                          ),
                          const DashedDivider(indent: AppSpacing.sm),
                          AccountRow(
                            label: l10n.fieldCarYear,
                            value: '${request.carYear}',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TitledCard(
                      title: l10n.cardSellerTitle,
                      child: Column(
                        children: <Widget>[
                          AccountRow(
                            label: l10n.fieldSellerPhone,
                            value: request.sellerPhone,
                          ),
                          const DashedDivider(indent: AppSpacing.sm),
                          AccountRow(
                            label: l10n.fieldSellerName,
                            value: request.sellerName ?? l10n.marketOwnerUnknown,
                          ),
                          const DashedDivider(indent: AppSpacing.sm),
                          AccountRow(
                            label: l10n.fieldCity,
                            value: request.city,
                          ),
                          if (request.inspectionCenterName case final String name
                              when name.isNotEmpty) ...<Widget>[
                            const DashedDivider(indent: AppSpacing.sm),
                            AccountRow(
                              label: l10n.fieldInspectionCentre,
                              value: name,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (request.clientNotes case final String notes
                        when notes.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppSpacing.md),
                      TitledCard(
                        title: l10n.cardNotesTitle,
                        child: Text(notes, style: AppText.secondary(13)),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    // What the job pays *this* inspector, and the one action they
                    // have about it. Replaces the standing 150 SAR estimate: that
                    // figure was the platform's, and the price of a job is now
                    // whatever the buyer proposed minus the commission — or
                    // whatever the two of them agreed. An inspector reading a
                    // number the platform picked for them is an inspector who
                    // cannot tell what the job is worth.
                    InspectorEarningsCard(request: request),
                    const SizedBox(height: AppSpacing.xl),
                    _ActionSection(
                      status: request.status,
                      busy: action.isLoading,
                      onAccept: () => _confirmAccept(context, ref, request),
                      onStart: () => _start(context, ref, request),
                      onComplete: () => _confirmComplete(context, ref, request),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Accepting is a binding commitment to a buyer, not a toggle, so it is asked
  /// for before it is done — the same weight as the buyer's cancel. The question
  /// and the write live in [confirmAccept], shared with the market.
  Future<void> _confirmAccept(
    BuildContext context,
    WidgetRef ref,
    InspectionRequest request,
  ) => confirmAccept(context, ref, request);

  /// Starts an accepted job. No dialog — starting does not commit anyone to
  /// anything irreversible, it just begins the work. The write's loading and
  /// error states live in the shared controller, which the action section
  /// watches, so `busy` keeps the button disabled while it runs.
  Future<void> _start(
    BuildContext context,
    WidgetRef ref,
    InspectionRequest request,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);

    try {
      await ref
          .read(inspectionRequestControllerProvider.notifier)
          .start(request.id);
    } on InspectionFailure catch (failure) {
      if (!context.mounted) return;
      _showMessage(context, failure.message);
      return;
    } on Object {
      if (!context.mounted) return;
      _showMessage(context, l10n.errorGeneric);
      return;
    }

    if (!context.mounted) return;
    _showMessage(context, l10n.inspectorStarted);
  }

  /// Completing makes the buyer's dashboard read "report ready", so it is not
  /// the kind of step an inspector should hit by reflex either.
  ///
  /// It also opens the report form, because those are the same moment: the
  /// reference's Screen 5 is entered from a completed job and nowhere else, and
  /// an inspector who taps "complete" and is then asked to find the report
  /// somewhere else has been handed two steps where the product has one.
  Future<void> _confirmComplete(
    BuildContext context,
    WidgetRef ref,
    InspectionRequest request,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.completeConfirmTitle),
        content: Text(l10n.completeConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.actionKeep),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.actionComplete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref
          .read(inspectionRequestControllerProvider.notifier)
          .complete(request.id);
    } on InspectionFailure catch (failure) {
      if (!context.mounted) return;
      _showMessage(context, failure.message);
      return;
    } on Object {
      if (!context.mounted) return;
      _showMessage(context, l10n.errorGeneric);
      return;
    }

    if (!context.mounted) return;
    _showMessage(context, l10n.inspectorCompleted);
    await context.pushNamed(
      'reportEntry',
      pathParameters: {'id': request.id},
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ActionSection extends StatelessWidget {
  const _ActionSection({
    required this.status,
    required this.busy,
    required this.onAccept,
    required this.onStart,
    required this.onComplete,
  });

  final InspectionStatus status;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onStart;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    // Exhaustive over [InspectionStatus]: a new status is a new decision, not a
    // default. `busy` disables the action while a transition is in flight — via
    // the shared controller state, so a request that arrives already on another
    // status while one write is pending cannot be double-submitted.
    //
    // No icon on any of the three. The design's primary buttons carry their
    // meaning in the label — `🤝 قبول الطلب وبدء التنسيق`, `📄 اعتماد وإصدار
    // التقرير` — and a Material `Icon` next to an Arabic label is a second
    // symbol saying the same thing in a style the reference does not use.
    return switch (status) {
      InspectionStatus.pending => SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: busy ? null : onAccept,
          child: Text(l10n.actionAccept),
        ),
      ),
      InspectionStatus.accepted => SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: busy ? null : onStart,
          child: Text(l10n.actionStart),
        ),
      ),
      InspectionStatus.inProgress => SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: busy ? null : onComplete,
          child: Text(l10n.actionComplete),
        ),
      ),
      InspectionStatus.completed || InspectionStatus.cancelled => Text(
        l10n.inspectorSettledNote,
        textAlign: TextAlign.center,
        style: AppText.secondary(13),
      ),
    };
  }
}
