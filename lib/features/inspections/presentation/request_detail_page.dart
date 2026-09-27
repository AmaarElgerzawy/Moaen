import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/inspection_controller.dart';
import '../data/inspection_repository.dart';
import '../domain/inspection_draft.dart';
import '../domain/inspection_request.dart';
import 'widgets/request_widgets.dart';

/// One request in full, with the cancel action.
///
/// The cancel action lives here rather than on the card because cancelling is
/// not reversible and touches a real transaction. A buyer should have to have
/// arrived at the request they mean.
class RequestDetailPage extends ConsumerWidget {
  const RequestDetailPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<void> action = ref.watch(inspectionRequestControllerProvider);

    // Reading through the list provider rather than fetching by id: the detail
    // page is always reached from a list that already has the row, so this is a
    // cache hit, and a second network read could show a *different* status than
    // the row the buyer tapped.
    final AsyncValue<List<InspectionRequest>> requests = ref.watch(
      myRequestsProvider,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.actionViewDetails)),
      body: requests.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.errorGeneric)),
        data: (List<InspectionRequest> all) {
          final InspectionRequest? match = all
              .where((InspectionRequest r) => r.id == id)
              .firstOrNull;

          // A missing id is a navigation bug, not a data state: the row was on
          // screen a moment ago. Saying so plainly beats rendering an empty
          // screen that looks like a deleted request.
          if (match == null) return Center(child: Text(l10n.errorGeneric));

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: <Widget>[
              Text(
                match.reference,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  // See the note in `client_dashboard_page.dart`: no
                  // `textDirection` override, so the number inherits the
                  // ambient direction and lands on the correct edge.
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              StatusChip(status: match.status),
              const SizedBox(height: AppSpacing.lg),
              _Card(
                title: l10n.createSectionVehicle,
                children: <Widget>[
                  _Row(label: l10n.fieldCarMake, value: match.carMake),
                  _Row(label: l10n.fieldCarModel, value: match.carModel),
                  _Row(label: l10n.fieldCarYear, value: '${match.carYear}'),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Card(
                title: l10n.createSectionSeller,
                children: <Widget>[
                  _Row(label: l10n.fieldSellerPhone, value: match.sellerPhone),
                  _Row(
                    label: l10n.fieldSellerAddress,
                    value: match.sellerLocationAddress,
                  ),
                  _Row(label: l10n.fieldCity, value: match.city),
                  if (match.inspectionCenterName case final String name
                      when name.isNotEmpty)
                    _Row(label: l10n.fieldInspectionCentre, value: name),
                ],
              ),
              if (match.clientNotes case final String notes
                  when notes.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                _Card(
                  title: l10n.createSectionNotes,
                  children: <Widget>[
                    Text(notes, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              _Card(
                title: l10n.costTitle,
                children: <Widget>[
                  _Row(
                    label: l10n.costInspection,
                    value: CostEstimate.format(match.price),
                  ),
                  _Row(label: l10n.costTotal, value: CostEstimate.format(
                    match.price,
                  ), emphasise: true),
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
              if (match.status.isOpen)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: action.isLoading
                      ? null
                      : () => _confirmCancel(context, ref, match),
                  icon: const Icon(Icons.close),
                  label: Text(l10n.actionCancelRequest),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmCancel(
    BuildContext context,
    WidgetRef ref,
    InspectionRequest request,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.actionCancelConfirm),
        content: Text(l10n.actionCancelBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.actionKeep),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.actionCancelRequest),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // `l10n` was read before the dialog, so it is safe to use after the await.
    // Reading `AppLocalizations.of(context)` here would be a use of BuildContext
    // across an async gap.
    try {
      await ref
          .read(inspectionRequestControllerProvider.notifier)
          .cancel(request.id);
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
    _showMessage(context, l10n.requestCancelled);
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.emphasise = false});

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: text.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: emphasise
                  ? text.titleSmall?.copyWith(fontWeight: FontWeight.w800)
                  : text.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
