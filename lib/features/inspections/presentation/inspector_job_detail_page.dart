import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/inspection_controller.dart';
import '../data/inspection_repository.dart';
import '../domain/inspection_draft.dart';
import '../domain/inspection_request.dart';
import 'widgets/request_widgets.dart';

/// One request as the inspector sees it, with the status transition actions.
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
      appBar: AppBar(title: Text(l10n.actionViewDetails)),
      body: job.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.errorGeneric)),
        data: (InspectionRequest request) {
          final String? stateNote = switch (request.status) {
            InspectionStatus.pending => l10n.inspectorAvailableNote,
            InspectionStatus.accepted ||
            InspectionStatus.inProgress => l10n.inspectorAssignedNote,
            InspectionStatus.completed ||
            InspectionStatus.cancelled => null,
          };

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: <Widget>[
              Text(
                request.reference,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  // Deliberately no `textDirection` override: "MN-1001" is a
                  // single left-to-right run, so bidi renders it correctly
                  // inside the ambient RTL paragraph. Pinned in
                  // `test/features/inspections/rtl_layout_test.dart`.
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[StatusChip(status: request.status)],
              ),
              if (stateNote case final String note) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  note,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              DetailCard(
                title: l10n.createSectionVehicle,
                children: <Widget>[
                  DetailRow(label: l10n.fieldCarMake, value: request.carMake),
                  DetailRow(label: l10n.fieldCarModel, value: request.carModel),
                  DetailRow(label: l10n.fieldCarYear, value: '${request.carYear}'),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              DetailCard(
                title: l10n.createSectionSeller,
                children: <Widget>[
                  DetailRow(label: l10n.fieldSellerPhone, value: request.sellerPhone),
                  DetailRow(
                    label: l10n.fieldSellerAddress,
                    value: request.sellerLocationAddress,
                  ),
                  DetailRow(label: l10n.fieldCity, value: request.city),
                  if (request.inspectionCenterName case final String name
                      when name.isNotEmpty)
                    DetailRow(label: l10n.fieldInspectionCentre, value: name),
                ],
              ),
              if (request.clientNotes case final String notes
                  when notes.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                DetailCard(
                  title: l10n.createSectionNotes,
                  children: <Widget>[
                    Text(notes, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              DetailCard(
                title: l10n.costTitle,
                children: <Widget>[
                  DetailRow(
                    label: l10n.costInspection,
                    value: CostEstimate.format(request.price),
                  ),
                  DetailRow(
                    label: l10n.costTotal,
                    value: CostEstimate.format(request.price),
                    emphasise: true,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l10n.costEstimateNotice,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
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
    );
  }

  /// Accepting is a binding commitment to a buyer, not a toggle, so it is asked
  /// for before it is done — the same weight as the buyer's cancel.
  Future<void> _confirmAccept(
    BuildContext context,
    WidgetRef ref,
    InspectionRequest request,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.acceptConfirmTitle),
        content: Text(l10n.acceptConfirmBody(request.city)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.actionKeep),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.actionAccept),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref
          .read(inspectionRequestControllerProvider.notifier)
          .accept(request.id);
    } on InspectionFailure catch (failure) {
      if (!context.mounted) return;
      _showMessage(context, failure.message);
      return;
    } on Object {
      if (!context.mounted) return;
      _showMessage(context, l10n.errorGeneric);
      return;
    }

    // `l10n` was read before the dialog, so it is safe to use after the await,
    // and `context` is only touched under the mounted guards above.
    if (!context.mounted) return;
    _showMessage(context, l10n.inspectorAccepted);
  }

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
    return switch (status) {
      InspectionStatus.pending => _PrimaryAction(
        label: l10n.actionAccept,
        icon: Icons.check_circle_outline,
        onPressed: busy ? null : onAccept,
      ),
      InspectionStatus.accepted => _PrimaryAction(
        label: l10n.actionStart,
        icon: Icons.play_arrow,
        onPressed: busy ? null : onStart,
      ),
      InspectionStatus.inProgress => _PrimaryAction(
        label: l10n.actionComplete,
        icon: Icons.flag_outlined,
        onPressed: busy ? null : onComplete,
      ),
      InspectionStatus.completed || InspectionStatus.cancelled => Center(
        child: Text(
          l10n.inspectorSettledNote,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    };
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // Full width: a single action belongs to the whole request, not to a
    // column of a form. Pinned in the inspector RTL test.
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}