import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../domain/inspection_draft.dart';
import '../../domain/inspection_request.dart';
import 'design_widgets.dart';

/// The status of a request, as the design's pill.
///
/// No icon. The design's pills are text-only throughout, and an icon here would be
/// the one glyph on the card that the reference does not have. Colour is not the
/// only signal either: the label says the same thing in words, which is what
/// makes the chip readable to a colour-blind buyer — and this is the one place on
/// a card where a misread status has consequences.
///
/// The tones come from the design's own four pill treatments rather than from the
/// scheme's containers, so a status chip cannot shift hue when the seed changes
/// and silently mean something different.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.dense = false});

  final InspectionStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return AppPill(
      label: switch (status) {
        InspectionStatus.pending => l10n.statusPending,
        InspectionStatus.accepted => l10n.statusAccepted,
        InspectionStatus.inProgress => l10n.statusInProgress,
        InspectionStatus.completed => l10n.statusCompleted,
        InspectionStatus.cancelled => l10n.statusCancelled,
      },
      tone: switch (status) {
        // A settled inspection is the one outcome the buyer paid for, so it takes
        // the solid green. Everything still in motion is a soft tone, and
        // `cancelled` is neutral gray rather than a failure colour: the buyer
        // chose it, and red would read as an error.
        InspectionStatus.completed => PillTone.success,
        InspectionStatus.pending => PillTone.warning,
        InspectionStatus.inProgress => PillTone.action,
        InspectionStatus.accepted || InspectionStatus.cancelled =>
          PillTone.neutral,
      },
      fontSize: dense ? 11 : 12,
    );
  }
}

/// A titled section of a detail page.
///
/// The design's card language — a bordered white panel with a bold heading — and
/// shared by the buyer's request detail and the inspector's job detail so the two
/// views of the same request cannot drift apart.
class DetailCard extends StatelessWidget {
  const DetailCard({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DesignCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: AppText.title(15)),
          const SizedBox(height: AppSpacing.md),
          ...children,
        ],
      ),
    );
  }
}

/// A labelled value inside a [DetailCard].
///
/// Both sides flex. A `Row` hands non-flex children *unbounded* main-axis width,
/// and these labels are long sentences in Arabic — a fixed-width side would
/// overflow the card rather than wrap inside it.
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasise = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasise;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(flex: 2, child: Text(label, style: AppText.secondary(12))),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: emphasise
                  ? AppText.title(13, color: valueColor)
                  : AppText.title(13).copyWith(
                      fontWeight: FontWeight.w600,
                      color: valueColor,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A request as a tappable card, in the design's card language.
///
/// The reference leads with the car rather than the reference number, and shows
/// the status as a pill at the opposite end. The reference is still on the card —
/// the buyer's handle for the request, and the thing they read out to a seller —
/// but as the small gray line rather than as the headline, because the design
/// makes the *car* the headline and this widget is what renders the design's card.
class RequestCard extends StatelessWidget {
  const RequestCard({super.key, required this.request, this.onTap});

  final InspectionRequest request;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TitledCard(
        title: request.carDescription,
        onTap: onTap,
        trailingLabel: null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    // Tabular figures, so the number does not change width
                    // between rows as its digits change.
                    //
                    // Deliberately no `textDirection` override: "MN-9920" is a
                    // single left-to-right run, so bidi renders it correctly
                    // inside the ambient RTL paragraph, and forcing LTR would
                    // additionally flip the alignment to the wrong edge. Pinned
                    // in `test/features/inspections/rtl_layout_test.dart`.
                    request.reference,
                    style: AppText.secondary(12).copyWith(
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                StatusChip(status: request.status, dense: true),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    l10n.buyerOrderCity(request.city),
                    style: AppText.secondary(12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  CostEstimate.format(request.price),
                  style: AppText.title(13, color: AppColors.green),
                ),
              ],
            ),
            if (request.clientNotes case final String notes
                when notes.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              InfoStrip(
                child: Text(
                  notes,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.secondary(12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
