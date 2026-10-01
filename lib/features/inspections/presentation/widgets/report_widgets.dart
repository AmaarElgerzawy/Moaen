/// The building blocks of the A4 report — the one screen in the design that is
/// not a phone screen.
///
/// Split out from `design_widgets.dart` because it is genuinely a different
/// medium. Everything in that file is sized for a 390dp viewport: a 16dp page
/// inset, a 18dp card radius, 14sp body type. The report is a 794dp sheet of
/// paper — a 30dp horizontal inset, 10dp tiles, 10sp body type and a dashed
/// 1.5dp outline. Sharing a component between the two would mean every
/// parameter on it becoming optional, and an optional parameter on a design
/// primitive is a decision nobody ever reads.
///
/// The two files do share `AppColors`, `AppRadius` and `AppText`, which is where
/// the two mediums genuinely agree.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'design_widgets.dart';

/// The report's A4 geometry, in one place.
///
/// A4 at 96dpi is 794 x 1123. The report is laid out at that width and then
/// scaled, rather than laid out at whatever width the phone happens to be,
/// because a report is a fixed artefact: the buyer is going to look at the same
/// page proportions whoever opens it, and a layout that reflows from 360dp to
/// 500dp is not the same document twice.
///
/// Named `ReportSheet` rather than `ReportPage` because the screen that shows it
/// is `ReportPage`, and two types in the same feature with one name is a file
/// someone eventually imports the wrong one of.
abstract final class ReportSheet {
  /// 794dp — A4's width at 96dpi.
  static const double width = 794;

  /// 1123dp — A4's height at 96dpi.
  static const double height = 1123;

  /// The report's own padding: 24dp top and bottom, 30dp at the sides.
  static const EdgeInsets padding = EdgeInsets.fromLTRB(30, 24, 30, 24);

  /// The gap between the report's sections. Wider than a phone's, because the
  /// report is read at a distance — it is handed to a seller, or printed.
  static const double gap = 16;
}

/// The report's section heading: 15sp bold, with a 4dp green rule down its
/// right-hand side and an 8dp gap between the rule and the text.
///
/// The rule is on the *right* because the report is an RTL document, and the
/// rule marks the reading edge. It is drawn as a border on a zero-width box
/// rather than as a painted line so it scales with the page transform for free.
class ReportHeading extends StatelessWidget {
  const ReportHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: AppColors.green, width: 4),
        ),
      ),
      child: Text(
        text,
        style: AppText.title(15),
      ),
    );
  }
}

/// The report's verified strip: dark, 10dp corners, a 6dp green rule down its
/// right-hand side, and the Nafath badge at the other end.
class ReportVerifiedBar extends StatelessWidget {
  const ReportVerifiedBar({required this.statement, super.key});

  final String statement;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: AppColors.darkHeader,
        borderRadius: BorderRadius.all(Radius.circular(10)),
        border: Border(
          right: BorderSide(color: AppColors.green, width: 6),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              statement,
              style: AppText.secondary(12, color: Colors.white),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const ReportVerifiedPill(),
        ],
      ),
    );
  }
}

/// The report's Nafath badge: a dark-green pill in the bright mint the design
/// uses on the phone headers.
class ReportVerifiedPill extends StatelessWidget {
  const ReportVerifiedPill({this.label = 'نفاذ ✅ VERIFIED', super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.darkBadge,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: AppText.pill(12, color: AppColors.darkBadgeOn),
      ),
    );
  }
}

/// The report's masthead: the dark shield, the wordmark, the report number and
/// the QR placeholder, over a dashed rule.
///
/// One row with three children rather than a header and a title, because the
/// design puts all three on one baseline and the QR box's top edge is what
/// squares the row up.
class ReportMasthead extends StatelessWidget {
  const ReportMasthead({
    required this.reference,
    required this.date,
    this.qrPlaceholder = 'QR CODE',
    super.key,
  });

  final String reference;
  final String date;
  final String qrPlaceholder;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            // The shield tile. The glyph is the design's own emoji rather than an
            // icon: the report is a document that will be printed and
            // screenshotted, and an icon font does not travel with a print.
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.darkHeader,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Text('🛡', style: TextStyle(fontSize: 26)),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'معاين',
                    style: AppText.title(38, color: AppColors.textPrimary)
                        .copyWith(height: 1),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'MOAAYEN CERTIFIED',
                    style: AppText.wordmark(10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    reference,
                    style: AppText.title(15),
                  ),
                  const SizedBox(height: 2),
                  Text(date, style: AppText.secondary(11)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.small),
                border: Border.all(
                  color: AppColors.onDarkMuted,
                  width: 1.5,
                ),
              ),
              child: Text(
                qrPlaceholder,
                style: AppText.secondary(9),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const DashedReportRule(),
      ],
    );
  }
}

/// The report's dashed rule, at the report's 1px weight.
class DashedReportRule extends StatelessWidget {
  const DashedReportRule({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _ReportDashedPainter()),
    );
  }
}

class _ReportDashedPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = AppColors.cardBorder
      ..strokeWidth = 1;

    const double dash = 5;
    const double gap = 4;
    final double y = size.height / 2;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + dash, size.width), y),
        paint,
      );
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_ReportDashedPainter oldDelegate) => false;
}

/// The report's verdict banner: the headline and its paragraph on the left, and
/// the quality donut on the right, both on the dark surface.
class ReportBanner extends StatelessWidget {
  const ReportBanner({
    required this.headline,
    required this.body,
    required this.score,
    required this.scoreCaption,
    super.key,
  });

  final String headline;
  final String body;

  /// 0..100. Drives both the headline's percentage and the donut's sweep.
  final int score;

  final String scoreCaption;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.darkHeader,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  headline,
                  style: AppText.title(18, color: AppColors.mint),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(body, style: AppText.reportBody(12)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          QualityDonut(score: score, caption: scoreCaption),
        ],
      ),
    );
  }
}

/// The report's quality indicator: a green arc over a dark track with the
/// figure in the middle.
///
/// Painted rather than assembled from a `CircularProgressIndicator` because the
/// design's ring is a *conic gradient* — solid green for the scored part, then
/// the track — and a progress indicator draws a single-arc stroke on a ring
/// background, which reads as a different object at a glance.
class QualityDonut extends StatelessWidget {
  const QualityDonut({
    required this.score,
    required this.caption,
    this.size = 80,
    super.key,
  });

  /// 0..100.
  final int score;

  final String caption;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(
          fraction: (score / 100).clamp(0.0, 1.0),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '$score%',
                style: AppText.title(18, color: Colors.white).copyWith(
                  height: 1,
                ),
              ),
              Text(
                caption,
                style: AppText.secondary(8, color: AppColors.onDarkSoft)
                    .copyWith(height: 1.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.fraction});

  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    // A 62dp hole in an 80dp ring, so the stroke is 9dp wide.
    const double stroke = 9;
    final Rect arc = rect.deflate(stroke / 2);

    canvas.drawArc(
      arc,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = AppColors.donutTrack
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    if (fraction <= 0) return;
    canvas.drawArc(
      arc,
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      Paint()
        ..color = AppColors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt,
    );
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.fraction != fraction;
}

/// One of the report's four-up data tiles: a gray label over a bold value.
class ReportTile extends StatelessWidget {
  const ReportTile({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.row),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(AppRadius.tile),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: AppText.secondary(11)),
          const SizedBox(height: 3),
          Text(
            value,
            style: AppText.title(13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// A four-across row of [ReportTile]s.
///
/// A `Row` of `Expanded`s rather than a grid, because the report's tile count
/// is fixed at eight and a `GridView` would make a non-scrolling report scroll.
class ReportTileGrid extends StatelessWidget {
  const ReportTileGrid({required this.tiles, super.key});

  final List<ReportTile> tiles;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final ReportTile tile in tiles)
          SizedBox(width: _tileWidth(context), child: tile),
      ],
    );
  }

  /// A quarter of the report's content width, less the gaps between them.
  double _tileWidth(BuildContext context) {
    final double content =
        ReportSheet.width - ReportSheet.padding.horizontal;
    // Three gaps of 8dp between four columns.
    return (content - (AppSpacing.sm * 3)) / 4;
  }
}

/// The report's car blueprint: a three-by-two grid of labelled region chips
/// beside a drawn top view of the car.
///
/// The container is LTR — the design says `direction: ltr` — because the chips
/// are a *diagram* laid out left to right in reading order and the car outline
/// has to sit on the same side every time. The Arabic labels inside each chip
/// still render right-to-left; only the order of the grid is fixed.
class BlueprintPanel extends StatelessWidget {
  const BlueprintPanel({required this.regions, super.key});

  final List<BlueprintRegion> regions;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.inset),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(child: _chipGrid()),
            const SizedBox(width: AppSpacing.lg),
            const CarOutline(),
          ],
        ),
      ),
    );
  }

  Widget _chipGrid() {
    // A `Wrap` of fixed-width cells rather than a `GridView`: three across, six
    // rows, and a `GridView` would give the panel its own scroll view inside a
    // document that is already one long scroll.
    const double gap = AppSpacing.sm;
    final double width = (ReportSheet.width - ReportSheet.padding.horizontal * 2 -
            AppSpacing.lg -
            150 -
            gap * 2) /
        3;

    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: <Widget>[
        for (final BlueprintRegion region in regions)
          SizedBox(width: width, child: BlueprintChip(region: region)),
      ],
    );
  }
}

/// One labelled region of the car, with its verdict.
class BlueprintRegion {
  const BlueprintRegion({
    required this.key,
    required this.englishLabel,
    required this.arabicLabel,
    required this.verdict,
    this.warn = false,
  });

  final String key;
  final String englishLabel;
  final String arabicLabel;
  final String verdict;

  /// True for the one region the design paints orange — the repainted fender.
  final bool warn;
}

class BlueprintChip extends StatelessWidget {
  const BlueprintChip({required this.region, super.key});

  final BlueprintRegion region;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Stack(
        children: <Widget>[
          // The English key at the physical top-left and the Arabic at the
          // physical top-right, exactly as the design draws them. Both pinned to
          // LTR so neither is reordered by the panel's direction.
          PositionedDirectional(
            start: 0,
            top: 0,
            child: Text(
              region.englishLabel,
              textDirection: TextDirection.ltr,
              style: AppText.secondary(9),
            ),
          ),
          PositionedDirectional(
            end: 0,
            top: 0,
            child: Text(
              region.arabicLabel,
              style: AppText.secondary(9),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 22),
              child: Text(
                region.verdict,
                style: AppText.pill(
                  11,
                  color: region.warn ? AppColors.warning : AppColors.greenDeep,
                  background: region.warn
                      ? AppColors.warningSurface
                      : AppColors.successSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The report's drawn top view of the car, beside the region chips.
///
/// Three boxes, not an illustration: a rounded capsule for the body, a green bar
/// for the windscreen and a lighter one for the cabin. It is a *locator* — it
/// tells the reader which way up the chip grid is — and anything more detailed
/// would be a drawing of a specific car, which this report is not about.
class CarOutline extends StatelessWidget {
  const CarOutline({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 76,
      child: Stack(
        children: <Widget>[
          // The body.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.car),
                border: Border.all(
                  color: AppColors.blueprintOutline,
                  width: 3,
                ),
              ),
            ),
          ),
          // The green bar: the report's "this end is the flagged one" marker, at
          // the right of the car in the design.
          PositionedDirectional(
            end: 6,
            top: 10,
            bottom: 10,
            width: 34,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.green,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
          ),
          // The cabin.
          PositionedDirectional(
            start: 40,
            end: 48,
            top: 14,
            bottom: 14,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.blueprintGlass,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          // The orange nose marker, overhanging the body's top edge.
          PositionedDirectional(
            end: 50,
            top: -3,
            width: 22,
            height: 3,
            child: ColoredBox(color: AppColors.warning),
          ),
        ],
      ),
    );
  }
}

/// The report's efficiency table: a dark header row over alternating rules.
class ReportTable extends StatelessWidget {
  const ReportTable({required this.headings, required this.rows, super.key});

  final List<String> headings;
  final List<ReportTableRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          color: AppColors.darkHeader,
          padding: const EdgeInsets.all(AppSpacing.row),
          child: Row(
            children: <Widget>[
              for (int i = 0; i < headings.length; i++)
                Expanded(
                  flex: i == 0 ? 4 : 3,
                  child: Text(
                    headings[i],
                    textAlign: i == 0 ? TextAlign.start : TextAlign.start,
                    style: AppText.pill(12, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
        for (final ReportTableRow row in rows) row,
      ],
    );
  }
}

class ReportTableRow extends StatelessWidget {
  const ReportTableRow({
    required this.sector,
    required this.efficiency,
    required this.grade,
    required this.notes,
    super.key,
  });

  final String sector;

  /// 0..100, drawn as a bar by the caller.
  final int efficiency;

  /// The band this percentage falls in, already written in the document's
  /// language — `95% (ممتاز)`, `80% (مقبول)`.
  ///
  /// Passed in rather than derived here, and that is the point. The reference's
  /// grade words are part of a sentence, so they belong in the ARB with the rest
  /// of the document's words; hard-coding them in this widget would print Arabic
  /// on an English device and would give the verdict banner and this table two
  /// independent thresholds that could drift apart. The caller derives the band
  /// once, from `ReportQualityBand.forPercent`, and both read it.
  final String grade;

  final String notes;

  /// The design's one orange row, identified by its efficiency rather than by an
  /// index: an inspector marking a sector "acceptable" should get the same
  /// colour whichever row it is, and a row-number rule would break the moment
  /// the report's sector list changed.
  bool get warn => efficiency < 90;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.row),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.cardBorder),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Text(
              sector,
              style: AppText.title(12),
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: EfficiencyBar(
                percent: efficiency,
                grade: grade,
                warn: warn,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(notes, style: AppText.secondary(12)),
          ),
        ],
      ),
    );
  }
}

/// The report's attachment grid: four dashed placeholders.
class ReportAttachments extends StatelessWidget {
  const ReportAttachments({required this.slots, super.key});

  final List<String> slots;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.row,
      runSpacing: AppSpacing.row,
      children: <Widget>[
        for (final String slot in slots)
          SizedBox(
            width: (ReportSheet.width - ReportSheet.padding.horizontal -
                    AppSpacing.row * 3) /
                4,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: AppSpacing.lg,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(AppRadius.tile),
                border: Border.all(
                  color: AppColors.dashed,
                  width: 1.5,
                ),
              ),
              child: Text(
                slot,
                textAlign: TextAlign.center,
                style: AppText.secondary(11),
              ),
            ),
          ),
      ],
    );
  }
}

/// The report's footer: the disclaimer on one side and the digital-certification
/// stamp on the other.
class ReportFooter extends StatelessWidget {
  const ReportFooter({
    required this.disclaimerLabel,
    required this.disclaimer,
    this.invoiceNumber,
    super.key,
  });

  final String disclaimerLabel;
  final String disclaimer;

  /// Folded into the disclaimer text where it appears. Null when the report
  /// records no centre invoice, which is the case before a centre is booked.
  final String? invoiceNumber;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: '$disclaimerLabel ',
                  style: AppText.title(10),
                ),
                TextSpan(text: disclaimer, style: AppText.secondary(10)),
              ],
            ),
            style: AppText.secondary(10).copyWith(height: 1.7),
          ),
        ),
        const SizedBox(width: AppSpacing.xl),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.inset,
            vertical: AppSpacing.row,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.green, width: 1.5),
          ),
          child: Text(
            'معاين MOAAYEN\nمُعتمد إلكترونياً 100%',
            textAlign: TextAlign.center,
            style: AppText.pill(10, color: AppColors.green).copyWith(
              height: 1.7,
            ),
          ),
        ),
      ],
    );
  }
}
