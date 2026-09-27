import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../domain/inspection_draft.dart';
import '../../domain/inspection_request.dart';

/// The status of a request, as a coloured pill.
///
/// Colour is not the only signal: the label says the same thing in words. A
/// status conveyed by hue alone is unreadable to a colour-blind buyer, and this
/// is the one place on the screen where a misread status has consequences.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.dense = false});

  final InspectionStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context);

    final (Color background, Color foreground, IconData icon) =
        switch (status) {
          InspectionStatus.pending => (
            colors.tertiaryContainer,
            colors.onTertiaryContainer,
            Icons.hourglass_empty,
          ),
          InspectionStatus.accepted => (
            colors.secondaryContainer,
            colors.onSecondaryContainer,
            Icons.person_pin_circle_outlined,
          ),
          InspectionStatus.inProgress => (
            colors.primaryContainer,
            colors.onPrimaryContainer,
            Icons.build_outlined,
          ),
          InspectionStatus.completed => (
            colors.primary,
            colors.onPrimary,
            Icons.check_circle_outline,
          ),
          InspectionStatus.cancelled => (
            colors.surfaceContainerHighest,
            colors.onSurfaceVariant,
            Icons.cancel_outlined,
          ),
        };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.sm : AppSpacing.md,
        vertical: dense ? 2 : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: dense ? 12 : 16, color: foreground),
          const SizedBox(width: AppSpacing.xs),
          Text(
            switch (status) {
              InspectionStatus.pending => l10n.statusPending,
              InspectionStatus.accepted => l10n.statusAccepted,
              InspectionStatus.inProgress => l10n.statusInProgress,
              InspectionStatus.completed => l10n.statusCompleted,
              InspectionStatus.cancelled => l10n.statusCancelled,
            },
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A request as a tappable row: car, reference, status, price.
class RequestCard extends StatelessWidget {
  const RequestCard({super.key, required this.request, this.onTap});

  final InspectionRequest request;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  // The reference is the buyer's handle for this request, so it
                  // leads. Under RTL it sits on the right, which is where the
                  // eye starts.
                  Text(
                    request.reference,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      // Tabular figures, so the number does not change width
                      // between rows as the digits change.
                      //
                      // Deliberately no `textDirection` override: "MN-9920" is a
                      // single left-to-right run, so bidi renders it correctly
                      // inside the ambient RTL paragraph, and forcing LTR would
                      // additionally flip the alignment to the wrong edge.
                      // Pinned in `test/features/inspections/rtl_layout_test.dart`.
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  const Spacer(),
                  StatusChip(status: request.status, dense: true),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                request.carDescription,
                style: theme.textTheme.bodyLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.location_on_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      request.city,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    CostEstimate.format(request.price),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (request.clientNotes case final String notes
                  when notes.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    notes,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
              if (onTap != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      l10n.actionViewDetails,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    // Not a hard-coded arrow. An arrow glyph points the wrong way
                    // under RTL unless it is mirrored, and the mirrored variant
                    // is not always available in the icon font.
                    Icon(
                      Icons.chevron_right,
                      textDirection: TextDirection.ltr,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
