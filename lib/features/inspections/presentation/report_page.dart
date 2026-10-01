import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/saudi_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/inspection_controller.dart';
import '../domain/inspection_report.dart';
import '../domain/inspection_request.dart';
import 'widgets/design_widgets.dart';
import 'widgets/report_widgets.dart';

/// Screen 6: the certified A4 report.
///
/// The one screen in the design that is not a phone screen — the reference draws
/// it with no frame around it, as a sheet of paper. So the page is a dark desk
/// with a white sheet lying on it, laid out at [ReportSheet.width] and scaled down
/// to whatever the viewport happens to be. Not the reverse: laying the report out
/// at the viewport's width and letting it reflow would give the buyer a different
/// document on a 360dp phone than on a 500dp one, and this is the artefact they
/// hand to a seller and print.
///
/// RTL, like every other Arabic document in the app, with the single exception of
/// the blueprint panel — the design marks that one `direction: ltr` and
/// [BlueprintPanel] honours it itself.
///
/// Reachable from the buyer's reports tab, the inspector's job detail and
/// straight after the entry form's issue button: one page, one document.
class ReportPage extends ConsumerWidget {
  const ReportPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<ReportBundle?> bundle = ref.watch(reportBundleProvider(id));

    return Scaffold(
      // The desk. The report is a white page; without a dark surround it would be
      // a white screen with a shadow, which reads as a card rather than as paper.
      backgroundColor: AppColors.darkHeader,
      body: SafeArea(
        child: Expanded(
          child: bundle.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            error: (_, _) => Center(
              child: DesignRetry(
                message: l10n.reportLoadError,
                actionLabel: l10n.actionRetry,
                onRetry: () => ref.invalidate(reportBundleProvider(id)),
              ),
            ),
            data: (ReportBundle? loaded) {
              if (loaded == null) {
                return Center(
                  child: DesignEmpty(
                    title: l10n.errorGeneric,
                    body: l10n.reportEntryUnavailable,
                  ),
                );
              }
              // An unissued report is a draft, not a document: its sectors may be
              // half-written and its headline figure may be a derivation rather
              // than an attestation. The design draws the seal, the donut and the
              // whole table as things a document *has*, so showing a draft in
              // that shape would print findings the inspector has not made.
              if (!loaded.report.isCertified) {
                return Center(
                  child: DesignEmpty(
                    title: l10n.reportsTitle,
                    body: l10n.reportNotReady,
                  ),
                );
              }
              return _Sheet(bundle: loaded);
            },
          ),
        ),
      ),
    );
  }
}

/// The bar above the paper, and the paper.
///
/// One widget rather than a bar and a document as siblings, because the bar's
/// title is the document's own reference number and there is no reason for the
/// two to be built from the bundle separately.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.bundle});

  final ReportBundle bundle;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Column(
      children: <Widget>[
        _SheetBar(title: l10n.reportNumberLabel(bundle.request.reference)),
        Expanded(
          // `FittedBox` rather than `Transform.scale`: a transform leaves the
          // laid-out box at 794 wide, so the scroll view would think the page is
          // `1123 / scale` tall and the report would either be clipped or have a
          // screenful of blank paper under it. A `FittedBox` measures the child
          // *after* scaling, which is exactly the scroll extent wanted.
          child: SingleChildScrollView(
            child: FittedBox(
              fit: BoxFit.fitWidth,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: ReportSheet.width,
                child: _Document(bundle: bundle),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The bar above the paper: a close square and the document's own number.
///
/// Not part of the document, and the only part of this screen that is a phone
/// screen at all. The design draws the A4 with no chrome, so this is the minimum
/// needed to leave it — a back affordance, in the shell's dark header, in the
/// same 40dp dark-square treatment the phone screens use for their back control.
class _SheetBar extends StatelessWidget {
  const _SheetBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      color: AppColors.darkHeader,
      child: Row(
        children: <Widget>[
          // `canPop` before `pop` rather than a bare `pop`: the A4 is always
          // pushed, so there is normally something to pop, and a deep link
          // straight to the report is the case where there is not. Popping
          // regardless would throw rather than simply do nothing.
          InkWell(
            onTap: () {
              if (context.canPop()) context.pop();
            },
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.darkSquare,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Text(
                '✕',
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(title, style: AppText.title(15, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

/// The A4 itself.
class _Document extends StatelessWidget {
  const _Document({required this.bundle});

  final ReportBundle bundle;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final SaudiFormat format = SaudiFormat(
      Localizations.localeOf(context).toString(),
    );

    // The centre's fee is folded into the request rather than read off the report,
    // for the reason `ReportBundle.requestWithCentre` gives: the request carries
    // the centre's *name* and the centre table carries its *fee*, and a report
    // that took one from each could print a name and an invoice for two different
    // centres.
    final InspectionRequest request = bundle.requestWithCentre;
    final InspectionReport report = bundle.report;

    // The headline figure. A stored value wins; a report written before its
    // sectors were recorded has none, and falls back to the same derivation the
    // issue path used, so the two can never disagree about a number that is
    // printed on the document.
    final int quality =
        report.qualityScore ?? ReportSectorScoring.summary(bundle.sections) ?? 0;

    return Container(
      width: ReportSheet.width,
      color: Colors.white,
      padding: ReportSheet.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ReportVerifiedBar(statement: l10n.reportVerifiedTop),
          ReportMasthead(
            reference: l10n.reportNumberLabel(request.reference),
            // The date the report was issued, not the date the request was
            // filed. A document is dated when it is signed.
            date: l10n.reportDateLabel(
              format.longDate(report.certifiedAt ?? request.createdAt),
            ),
          ),
          ReportBanner(
            headline: l10n.reportVerdictHeadline(_grade(l10n, quality)),
            // The inspector's own summary when there is one; the design's own
            // paragraph is the fallback rather than the text. That paragraph
            // describes a clean inspection, and for a report that recorded
            // faults it would be a sentence nobody wrote, on a document somebody
            // is signing.
            body: report.resultSummary?.trim().isNotEmpty ?? false
                ? report.resultSummary!.trim()
                : l10n.reportVerdictBody,
            score: quality,
            scoreCaption: l10n.reportQualityCaption,
          ),
          ReportHeading(l10n.reportVehicleSection),
          ReportTileGrid(tiles: _tiles(l10n, request, report)),
          // Two sections that render only what was recorded. The design's
          // blueprint shows six graded regions and its table four scored ones;
          // drawing either frame with nothing inside it would assert a car that
          // was never graded, and the frame is the part of a report a reader
          // trusts most.
          if (bundle.parts.isNotEmpty) ...<Widget>[
            ReportHeading(l10n.reportBlueprintSection),
            BlueprintPanel(
              regions: <BlueprintRegion>[
                for (final ReportPart part in bundle.parts)
                  BlueprintRegion(
                    key: part.partKey,
                    englishLabel: part.labelEn,
                    arabicLabel: part.labelAr,
                    verdict: part.verdict,
                    // The stored tone, not the verdict's wording: the design's one
                    // orange chip is a *warning*, and an inspector who wrote
                    // "needs repair" on a region should get the warning colour
                    // rather than a green one for spelling it differently.
                    warn: part.tone != ReportPartTone.good,
                  ),
              ],
            ),
          ],
          if (bundle.sections.isNotEmpty) ...<Widget>[
            ReportHeading(l10n.reportEfficiencySection),
            ReportTable(
              headings: <String>[
                l10n.reportTableSector,
                l10n.reportTableEfficiency,
                l10n.reportTableNotes,
              ],
              rows: <ReportTableRow>[
                for (final ReportSection section in bundle.sections)
                  ReportTableRow(
                    // The design numbers its rows in the first column —
                    // `1. المحرك والميكانيكا`. The ordinal is part of the
                    // document, so it is composed here; the stored label is just
                    // the sector's name and has no idea where it sits.
                    sector: '${section.ordinal}. ${section.label}',
                    efficiency: section.efficiency,
                    // The same band, from the same thresholds, that the verdict
                    // banner above is graded by — so the headline percentage and
                    // the row that produced it cannot call one figure ممتاز and
                    // the other سليم.
                    grade: _grade(l10n, section.efficiency),
                    // Null notes render as an empty cell rather than a dash: the
                    // column is "the inspector's remarks", and a sector with none
                    // has none — it is not a value that failed to load.
                    notes: section.notes ?? '',
                  ),
              ],
            ),
          ],
          ReportHeading(l10n.reportAttachmentsSection),
          ReportAttachments(
            slots: <String>[
              l10n.reportAttachmentCorners,
              l10n.reportAttachmentOdometer,
              l10n.reportAttachmentEngine,
              l10n.reportAttachmentInvoice,
            ],
          ),
          ReportFooter(
            disclaimerLabel: l10n.reportDisclaimerLabel,
            // The template names the centre's invoice in the middle of the
            // sentence, so a report without one cannot be printed from it without
            // leaving a blank where a document number belongs. Saying so is the
            // honest version; printing "N/A" would be neither.
            disclaimer: l10n.reportDisclaimerBody(
              report.centerInvoiceNo?.trim().isNotEmpty ?? false
                  ? report.centerInvoiceNo!.trim()
                  : l10n.reportNoInvoice,
            ),
            invoiceNumber: report.centerInvoiceNo,
          ),
        ],
      ),
    );
  }

  /// The headline's grade word, from the report's own vocabulary.
  ///
  /// The same four words the efficiency table already prints, chosen by the same
  /// thresholds — see [ReportQualityBand].
  String _grade(AppLocalizations l10n, int percent) =>
      switch (ReportQualityBand.forPercent(percent)) {
        ReportQualityBand.excellent => l10n.reportGradeExcellent,
        ReportQualityBand.sound => l10n.reportGradeSound,
        ReportQualityBand.acceptable => l10n.reportGradeAcceptable,
        ReportQualityBand.needsRepair => l10n.reportGradeNeedsRepair,
      };

  /// The eight data tiles, in the design's order.
  List<ReportTile> _tiles(
    AppLocalizations l10n,
    InspectionRequest request,
    InspectionReport report,
  ) => <ReportTile>[
    ReportTile(label: l10n.reportTileVehicle, value: request.carDescription),
    // `—` for a value nobody recorded. Not an empty string: a tile with a blank
    // where a value belongs reads as a rendering fault, and a tile reading `—`
    // reads as what it is — a column that exists and is unpopulated.
    ReportTile(label: l10n.reportTilePlate, value: request.plateNumber ?? _absent),
    ReportTile(label: l10n.reportTileVin, value: request.vin ?? _absent),
    ReportTile(
      label: l10n.reportTileOdometer,
      value: request.odometerKm == null
          ? _absent
          : l10n.reportOdometerValue(_thousands(request.odometerKm!)),
    ),
    ReportTile(label: l10n.reportTileCity, value: request.city),
    ReportTile(
      label: l10n.reportTileCentre,
      value: request.inspectionCenterName ?? _absent,
    ),
    ReportTile(
      label: l10n.reportTileInspector,
      value: request.inspectorName ?? _absent,
    ),
    ReportTile(
      label: l10n.reportTileInvoice,
      value: report.centerInvoiceNo ?? _absent,
    ),
  ];

  /// The design's odometer grouping: `516,778`.
  ///
  /// Hand-rolled rather than `NumberFormat('#,###')` because that would take its
  /// digits — and its separator — from the locale, and this document uses Western
  /// digits in an Arabic one throughout. See `SaudiFormat` for the same argument
  /// about Arabic-Indic digits.
  static String _thousands(int km) {
    final String digits = km.toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  static const String _absent = '—';
}
