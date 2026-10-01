/// The building blocks the approved design is assembled from.
///
/// The design is six screens drawn from one system, and this file is that system.
/// Everything here is a *primitive the design names* — the dark header with its
/// 28dp bottom corners, the dashed rule, the yellow notice box, the light-green
/// pill, the text-only bottom bar — rather than a generic component library. When
/// a screen needs something the design has not got, it belongs on the screen, not
/// here.
///
/// Two conventions run through all of it:
///
///  * **Physical direction.** The design fixes some regions as LTR containers and
///    some as RTL ones regardless of the app's locale, so those are pinned with
///    [LtrRegion] / [RtlRegion] rather than left to the ambient direction. Arabic
///    text inside an [LtrRegion] still lays out right-to-left; only the *order of
///    the items* is fixed, which is what the design actually specifies.
///  * **Tokens, not literals.** Every colour, radius and gap comes from
///    `AppColors` / `AppRadius` / `AppSpacing`, so a token change re-skins all six
///    screens at once.
library;

import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;

import '../../../../core/theme/app_theme.dart';

/// Pins a subtree to LTR item order, whatever the app's locale is.
///
/// The design's invoice box, contact box, headers and bottom bars are laid out
/// left-to-right on the physical screen. Under the Arabic locale the ambient
/// direction would reverse them, so they are wrapped in this.
class LtrRegion extends StatelessWidget {
  const LtrRegion({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Directionality(textDirection: TextDirection.ltr, child: child);
}

/// Pins a subtree to RTL item order. The default under the Arabic locale, but
/// stated explicitly on the screens the design marks as RTL containers so the
/// intent survives a locale change.
class RtlRegion extends StatelessWidget {
  const RtlRegion({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Directionality(textDirection: TextDirection.rtl, child: child);
}

/// The dark header every screen opens with.
///
/// Two shapes, because the design uses two. A header that bleeds off the top of
/// the screen has square top corners and rounds only at the bottom (28dp); one
/// that sits inside the page — the green request card's header treatment, or any
/// header reused mid-scroll — rounds on all four.
class DarkHeader extends StatelessWidget {
  const DarkHeader({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.bleed = true,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// True for a page-top header that runs off the top edge of the screen.
  final bool bleed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.darkHeader,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(bleed ? AppRadius.header : AppRadius.card),
          top: Radius.circular(bleed ? 0 : AppRadius.card),
        ),
      ),
      child: child,
    );
  }
}

/// The square button that sits on a dark header.
///
/// Empty by design on the buyer home — the design shows a bare rounded square
/// with no glyph, a placeholder for a notification button that does not exist
/// yet. An iconless control that a user can see but not press is a lie about
/// what the app does, so [onTap] is optional and the box is inert when it is
/// null.
class HeaderSquare extends StatelessWidget {
  const HeaderSquare({
    this.child,
    this.onTap,
    this.size = 52,
    this.borderRadius = 16,
    super.key,
  });

  final Widget? child;
  final VoidCallback? onTap;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final Widget box = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.darkSquare,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: child,
    );

    if (onTap == null) return box;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: box,
      ),
    );
  }
}

/// The green circle avatar: the design's white initial on the brand green.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar({
    required this.name,
    this.diameter = 56,
    this.background = AppColors.green,
    this.foreground = Colors.white,
    this.borderColor,
    this.borderWidth = 0,
    super.key,
  });

  final String name;

  final double diameter;
  final Color background;
  final Color foreground;
  final Color? borderColor;
  final double borderWidth;

  /// The first character, upper-cased.
  ///
  /// Arabic has no case, so `toUpperCase` is a no-op on the Arabic initial the
  /// Arabic locale produces; it only matters for a Latin name.
  String get initial {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: borderWidth),
      ),
      child: Text(
        initial,
        style: AppText.title(diameter * 0.4, color: foreground),
      ),
    );
  }
}

/// The design's dashed rule.
///
/// A `Divider` is solid and the design is explicit that these are dashed, so this
/// paints one. The dashes are drawn as evenly spaced segments along the axis,
/// which is what keeps a dashed line looking like a dashed line at any width
/// instead of stretching a few long marks across a wide box.
class DashedDivider extends StatelessWidget {
  const DashedDivider({
    this.color = AppColors.dashed,
    this.dashWidth = 5,
    this.gap = 4,
    this.thickness = 1,
    this.indent = 0,
    super.key,
  });

  final Color color;
  final double dashWidth;
  final double gap;
  final double thickness;

  /// Blank space before the rule starts, for a rule that should not run the full
  /// width of its container.
  final double indent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: thickness,
      child: CustomPaint(
        painter: _DashedLinePainter(
          color: color,
          dashWidth: dashWidth,
          gap: gap,
          thickness: thickness,
          indent: indent,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({
    required this.color,
    required this.dashWidth,
    required this.gap,
    required this.thickness,
    required this.indent,
  });

  final Color color;
  final double dashWidth;
  final double gap;
  final double thickness;
  final double indent;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    final double y = size.height / 2;
    final double step = dashWidth + gap;
    double x = indent;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + dashWidth, size.width), y),
        paint,
      );
      x += step;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) =>
      old.color != color ||
      old.dashWidth != dashWidth ||
      old.gap != gap ||
      old.thickness != thickness ||
      old.indent != indent;
}

/// A box with a dashed outline: the report-entry screen's "add photo" tile, and
/// the QR placeholder on the A4.
///
/// Flutter has no dashed border — [BorderStyle] only offers `solid` and `none` —
/// so this paints the four edges itself. It exists because the alternative is a
/// solid hairline, and on a white tile a solid hairline reads as *filled* rather
/// than as an invitation: the whole point of the tile is that there is nothing
/// there yet.
class DashedBorderBox extends StatelessWidget {
  const DashedBorderBox({
    required this.child,
    this.color = AppColors.onDarkMuted,
    this.radius = 12,
    this.thickness = 1.5,
    this.dashWidth = 5,
    this.gap = 4,
    super.key,
  });

  final Widget child;
  final Color color;
  final double radius;
  final double thickness;
  final double dashWidth;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBoxPainter(
        color: color,
        radius: radius,
        thickness: thickness,
        dashWidth: dashWidth,
        gap: gap,
      ),
      child: child,
    );
  }
}

class _DashedBoxPainter extends CustomPainter {
  const _DashedBoxPainter({
    required this.color,
    required this.radius,
    required this.thickness,
    required this.dashWidth,
    required this.gap,
  });

  final Color color;
  final double radius;
  final double thickness;
  final double dashWidth;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    final Rect rect = Offset.zero & size;
    final RRect rrect = RRect.fromRectAndRadius(
      rect.deflate(thickness / 2),
      Radius.circular(radius),
    );
    final Path path = Path()..addRRect(rrect);

    // Dashes measured along the path's own length rather than per edge, so a
    // wide tile and a narrow one get the same dash pattern instead of one
    // stretching its handful of marks across the whole run.
    for (final PathMetric metric in path.computeMetrics()) {
      double travelled = 0;
      while (travelled < metric.length) {
        final double end = math.min(travelled + dashWidth, metric.length);
        canvas.drawPath(
          metric.extractPath(travelled, end),
          paint,
        );
        travelled += dashWidth + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBoxPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.thickness != thickness ||
      old.dashWidth != dashWidth ||
      old.gap != gap;
}

/// A pill or badge.
///
/// The design uses four variants and they are not interchangeable — a light-green
/// pill on white, a dark-green pill on a dark header, a pale-orange warning
/// badge, and a white-on-dark action pill — so they are named rather than left to
/// a `color` parameter, which is how a "light-green fill" ends up with the wrong
/// text contrast.
enum PillTone {
  success,
  onDark,
  warning,
  neutral,
  action,

  /// The design's "available for work" chip: the bright mint on the dark header,
  /// with the header's own near-black as its text. Distinct from [onDark] on
  /// purpose — the two sit at opposite ends of the same header row, and reusing one
  /// treatment for both would make the inspector's availability read as another
  /// verification badge.
  highlight,

  /// WhatsApp's own brand green, for the one control that opens WhatsApp.
  ///
  /// Named here rather than left to the caller because a caller's `background`
  /// argument would be a colour no reader could trace back to a place in the
  /// design; the same argument as [AppColors.green] is the app's green, and
  /// opening WhatsApp from something that looks like the app's own green button is
  /// a lie about what will happen.
  whatsapp,

  /// White fill, green text. The report-entry header's request pill, and the only
  /// pill in the app with a light fill on the dark header — every other one is
  /// dark-on-dark or green-on-light, so this one is its own thing rather than a
  /// parameter.
  inverse,
}

class AppPill extends StatelessWidget {
  const AppPill({
    required this.label,
    this.tone = PillTone.success,
    this.icon,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    this.fontSize = 12,
    this.onTap,
    super.key,
  });

  final String label;
  final PillTone tone;
  final IconData? icon;
  final EdgeInsetsGeometry padding;

  /// Makes the pill a control.
  ///
  /// The reference draws several of its pills as buttons — the two contact chips
  /// on the task card, the accept chip on each board row — and a pill that cannot
  /// be pressed is not a faithful reproduction of a control, it is a label shaped
  /// like one. Null leaves the pill non-interactive, which is what a status chip
  /// wants.
  ///
  /// A null [onTap] while a pill is styled as a button (`action`, `whatsapp`) is
  /// rendered greyed out rather than live, so a control the code could not wire up
  /// does not invite a tap that does nothing.
  final VoidCallback? onTap;

  /// The design varies a pill's type by context: 11dp on a step's status chip,
  /// 12dp on the market's city pill, 10dp on the inspector's verified badge.
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color foreground) = switch (tone) {
      PillTone.success => (AppColors.successSurface, AppColors.greenDeep),
      PillTone.onDark => (AppColors.darkBadge, AppColors.darkBadgeOn),
      // The design's warning pill is a flat pale orange, not a tint of the orange
      // at low alpha. They are visibly different colors on a real screen, and a
      // tint would drift as the orange is ever so slightly adjusted.
      PillTone.warning => (AppColors.warningSurface, AppColors.warning),
      PillTone.neutral => (AppColors.inputFill, AppColors.textSecondary),
      PillTone.action => (AppColors.darkSurface, Colors.white),
      PillTone.highlight => (AppColors.mint, AppColors.darkHeader),
      PillTone.whatsapp => (AppColors.whatsappFill, AppColors.whatsappOn),
      PillTone.inverse => (Colors.white, AppColors.green),
    };

    // A control with no handler is dimmed rather than left live. The disabled
    // treatment belongs to the tap, not to the shape: a status chip is not
    // disabled, it is simply not a control.
    final bool inert = onTap == null &&
        (tone == PillTone.action || tone == PillTone.whatsapp);
    final Color fill = inert ? AppColors.inputFill : background;
    final Color ink = inert ? AppColors.textSecondary : foreground;

    final Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: tone == PillTone.success
            ? Border.all(color: AppColors.successBorder)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14, color: ink),
            const SizedBox(width: AppSpacing.xs),
          ],
          // The design's pills carry their own emoji (`📍`, `🔴`, `🔒`) inside the
          // label string, so the text is not padded with a separate icon here.
          Flexible(
            child: Text(
              label,
              style: AppText.pill(fontSize, color: ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return Semantics(label: label, child: body);
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: body,
      ),
    );
  }
}

/// The design's red "live" indicator: a dot plus its label.
///
/// The dot is static. An infinite pulse animation would never let
/// `pumpAndSettle` settle, and a test that has to special-case a permanent
/// animation is a test that will be flaky for everyone who adds a screen after it.
/// The design reads as live from the red alone.
class LiveBadge extends StatelessWidget {
  const LiveBadge({required this.label, this.dense = false, super.key});

  final String label;

  /// Drops the dot and shrinks the type, for the inspector's task card where the
  /// indicator sits on a white background next to a heading.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: dense ? 7 : 8,
          height: dense ? 7 : 8,
          decoration: const BoxDecoration(
            color: AppColors.live,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: AppText.pill(dense ? 12 : 13, color: AppColors.live),
        ),
      ],
    );
  }
}

/// The yellow notice box.
///
/// Used where the design calls out something the reader must not skim past: the
/// buyer's appointment reminder, the inspector's centre-and-time form. Brown on
/// cream rather than the theme's error colours, because it is a warning to read,
/// not a failure to recover from.
class NoticeBox extends StatelessWidget {
  const NoticeBox({
    required this.child,
    this.title,
    this.titleIcon,
    this.iconOnStart = true,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.borderRadius = 14,
    super.key,
  });

  final Widget child;

  /// Optional bold heading, rendered in the box's own brown.
  final String? title;
  final IconData? titleIcon;

  /// True on the buyer's notice, where the bell sits at the physical left edge
  /// and the text runs to its right.
  final bool iconOnStart;

  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.alertSurface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppColors.alertBorder),
      ),
      child: iconOnStart
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                if (titleIcon != null) ...<Widget>[
                  Icon(titleIcon, size: 20, color: AppColors.alertOn),
                  const SizedBox(width: AppSpacing.md),
                ],
                Expanded(child: _column()),
              ],
            )
          : _column(),
    );
  }

  /// The box's own body: the optional bold heading, then the caller's content.
  Column _column() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title != null) ...<Widget>[
          Text(title!, style: AppText.title(14, color: AppColors.alertOn)),
          const SizedBox(height: 6),
        ],
        child,
      ],
    );
  }
}

/// The light-green box that carries money: the cost structure on the create form
/// and the invoice on the buyer's home.
///
/// Green because it is the reassuring one — this is a breakdown the product is
/// standing behind, not a warning.
class CostBox extends StatelessWidget {
  const CostBox({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.borderRadius = 14,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.successSurface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppColors.successBorder),
      ),
      child: child,
    );
  }
}

/// The light-gray info strip: contact details, a request's poster and age.
///
/// The gray of the input fill, with a border, so a strip nested inside a white
/// card reads as inset rather than as another card.
class InfoStrip extends StatelessWidget {
  const InfoStrip({
    required this.child,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.md,
    ),
    this.borderRadius = 12,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: child,
    );
  }
}

/// A section heading on the page background.
///
/// The design left-aligns these on the two LTR-style screens and right-aligns
/// them on the RTL ones, so alignment is a parameter rather than inherited from
/// the ambient direction.
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    required this.text,
    this.alignment = TextAlign.start,
    this.fontSize = 16,
    this.color,
    super.key,
  });

  final String text;
  final TextAlign alignment;
  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: alignment,
      style: AppText.title(fontSize, color: color),
    );
  }
}

/// A bold label sitting above a field, the design's form-label role.
///
/// Always rendered at the region's start edge, which is why the screens that put
/// it on the right wrap their form in an [RtlRegion] and the ones that put it on
/// the left in an [LtrRegion].
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {this.color, super.key});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      // 12dp bold, the design's `.lbl`. Not 14: that is the `.card h3` size, and
      // a field label set at the card-title size stops reading as subordinate to
      // the card it sits in.
      child: Text(text, style: AppText.title(12, color: color)),
    );
  }
}

/// The text-only bottom bar.
///
/// Four destinations, no icons anywhere — which is the whole reason this is a
/// custom bar rather than Material's `NavigationBar`, whose destinations are
/// required to carry an icon. [items] is given in the design's order and
/// [ltr] controls which physical edge the first one lands on: the design puts
/// both bars' first tab at the physical left, and says so.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.ltr = true,
    super.key,
  });

  final List<BottomNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// True places the first item at the physical left, as the design specifies for
  /// both the buyer's and the inspector's bar.
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final Widget bar = Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < items.length; i++)
                Expanded(
                  child: _NavTab(
                    label: items[i].label,
                    selected: i == currentIndex,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return ltr ? LtrRegion(child: bar) : RtlRegion(child: bar);
  }
}

class BottomNavItem {
  const BottomNavItem(this.label);

  final String label;
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      // The design's active state is colour and weight only — no indicator pill —
      // so the ripple is clipped to the tab and nothing else changes.
      child: Center(
        child: Text(
          label,
          style: AppText.pill(
            13,
            color: selected ? AppColors.green : AppColors.textSecondary,
            weight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// One step of [StepTimeline].
///
/// Three visual states, and they are *not* the same as reached / not-reached:
///
///  * **done** — the brand green with a white tick.
///  * **current** — orange, holding a glyph rather than a tick. This is the step
///    the transaction is waiting on, and painting it green would claim work that
///    has not happened.
///  * **pending** — flat gray with the step's number.
///
/// [reached] counts a *done* step only. The current step is not done, so a
/// request at `accepted` shows one tick, not two — which is the invariant
/// `test/features/inspections/inspector_flow_test.dart` pins.
class TimelineStep {
  const TimelineStep({
    required this.title,
    required this.subtitle,
    this.glyph = '4',
  });

  final String title;
  final String subtitle;

  /// The character inside the circle when the step is current or pending. The
  /// design uses a pin on the appointment step and the step number elsewhere.
  final String glyph;
}

enum _StepState { done, current, pending }

/// The design's vertical four-step tracker: the circle at the region's start edge,
/// the title and subtitle beside it, and no connector line between steps.
///
/// The absence of a line is deliberate and looks like an oversight otherwise. A
/// connector implies a continuous path through time; the design's tracker is a
/// checklist, and the gap between rows is what makes it read that way.
class StepTimeline extends StatelessWidget {
  const StepTimeline({
    required this.steps,
    required this.reachedCount,
    this.ltr = false,
    super.key,
  });

  final List<TimelineStep> steps;

  /// How many steps are done, 0..[steps].length.
  final int reachedCount;

  /// True puts the circles at the physical left, as on the buyer's home.
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final Widget column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < steps.length; i++)
          _StepRow(
            step: steps[i],
            state: i < reachedCount
                ? _StepState.done
                : i == reachedCount
                ? _StepState.current
                : _StepState.pending,
            number: i + 1,
            isLast: i == steps.length - 1,
          ),
      ],
    );

    return ltr ? LtrRegion(child: column) : RtlRegion(child: column);
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.state,
    required this.number,
    required this.isLast,
  });

  final TimelineStep step;
  final _StepState state;
  final int number;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final (Color fill, Color border, Color glyphColor) = switch (state) {
      _StepState.done => (AppColors.green, AppColors.green, Colors.white),
      _StepState.current => (
        AppColors.warning.withValues(alpha: 0.16),
        AppColors.warning,
        AppColors.warning,
      ),
      _StepState.pending => (
        AppColors.inputFill,
        AppColors.cardBorder,
        AppColors.textSecondary,
      ),
    };

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // A `Row` hands non-flex children unbounded main-axis constraints, so
          // the circle keeps its intrinsic width and the text column is the one
          // that flexes. Reversing that is what makes a Row throw under RTL.
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: border),
            ),
            child: state == _StepState.done
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : Text(
                    state == _StepState.pending ? '$number' : step.glyph,
                    style: AppText.pill(
                      13,
                      color: glyphColor,
                      weight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(step.title, style: AppText.title(14)),
                const SizedBox(height: 2),
                Text(step.subtitle, style: AppText.secondary(12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The design's three-up stats bar: a translucent panel with thin vertical rules
/// between equal columns, each holding a small gray label above a bold white
/// value.
///
/// The columns are ordered right-to-left in the design even though the rest of the
/// inspector's header is left-to-right, which is why [ltr] is false here by
/// design: the caller wraps the whole bar and the order is fixed at the call
/// site.
class StatsBar extends StatelessWidget {
  const StatsBar({
    required this.stats,
    this.ltr = false,
    super.key,
  });

  final List<StatEntry> stats;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    // The design's bar is a bordered box and nothing else: no fill of its own, a
    // 1dp border at 18% white, and a hairline between the columns rather than
    // around them. A 5% white fill would read as a raised panel, which is a
    // different component from the one the reference draws.
    final Widget row = Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.row),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < stats.length; i++) ...<Widget>[
            if (i > 0)
              Container(
                width: 1,
                height: 32,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            Expanded(
              child: Column(
                children: <Widget>[
                  Text(
                    stats[i].label,
                    textAlign: TextAlign.center,
                    style: AppText.secondary(
                      11,
                      color: AppColors.onDarkMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stats[i].value,
                    textAlign: TextAlign.center,
                    style: AppText.onDark(14),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return ltr ? LtrRegion(child: row) : RtlRegion(child: row);
  }
}

class StatEntry {
  const StatEntry(this.label, this.value);

  final String label;
  final String value;
}

/// One card in the design's numbered section cards: an emoji title, an optional
/// small label at the opposite end, and a dashed rule beneath the title.
class TitledCard extends StatelessWidget {
  const TitledCard({
    required this.title,
    required this.child,
    this.trailingLabel,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.background = AppColors.surface,
    this.borderColor = AppColors.cardBorder,
    this.titleColor,
    this.onTap,
    super.key,
  });

  final String title;

  /// The small green label the design puts at the far end of a card's title row
  /// (`خط الفحص 01`).
  final String? trailingLabel;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color background;
  final Color borderColor;
  final Color? titleColor;

  /// Makes the whole card tappable. Used by the inspector's board rows, where
  /// the design puts the whole card behind the "قبول الطلب" pill.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget container = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: borderColor),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: AppText.title(14, color: titleColor),
                ),
              ),
              if (trailingLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    trailingLabel!,
                    style: AppText.pill(11, color: AppColors.green),
                  ),
                ),
            ],
          ),
          // The design's `.card h3` rule: a solid hairline that reads as dashed
          // at 1dp on a light background. Painted solid rather than dashed
          // because the card titles in the reference have already been given a
          // dashed rule of their own in the A4, and two different dashes on one
          // screen stop meaning anything.
          const SizedBox(height: AppSpacing.sm),
          const DashedDivider(),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );

    if (onTap == null) return container;

    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: container,
      ),
    );
  }
}

/// The design's plain card: white, 18dp corners, a hairline border and a 14dp
/// inset — with no title rule, because not every card in the reference has a
/// heading ([TitledCard] is the one that does).
class DesignCard extends StatelessWidget {
  const DesignCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.inset),
    this.background = AppColors.surface,
    this.borderColor = AppColors.cardBorder,
    this.borderRadius,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color background;
  final Color borderColor;

  /// Overridden to 20dp by the market's request card, which the design draws
  /// larger than every other card.
  final double? borderRadius;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget container = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(borderRadius ?? AppRadius.card),
        border: Border.all(color: borderColor),
        boxShadow: AppTheme.cardShadow,
      ),
      child: child,
    );

    if (onTap == null) return container;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(borderRadius ?? AppRadius.card),
      child: container,
    );
  }
}

/// The design's `.two`: two equal columns with a 10dp gap.
///
/// [flex] exists for the one place the reference is uneven — the create form's
/// city and plate row, where the city takes 1.3 and the plate 1. A `Row` with
/// `Expanded` children is the whole widget; naming the ratio here keeps the
/// 1.3 out of the screen.
class TwoUp extends StatelessWidget {
  const TwoUp({required this.children, this.flexLeft = 1, super.key})
    : assert(
        children.length == 2,
        'TwoUp is the design\'s two-column row; use a Row for anything else',
      );

  final List<Widget> children;
  final int flexLeft;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(flex: flexLeft, child: children[0]),
        const SizedBox(width: AppSpacing.row),
        Expanded(child: children[1]),
      ],
    );
  }
}

/// The design's read-only dropdown: the input fill, the current value, and the
/// `⌄` chevron on its own at the far end.
///
/// A distinct widget from a `TextFormField` because it must not be focusable.
/// Every one of these in the reference is a *choice already made or to be made
/// from a menu* — the engine verdict, the fender condition, the centre — and a
/// focusable field that accepts free text would let a buyer file a report whose
/// engine condition is a sentence.
class SelectField extends StatelessWidget {
  const SelectField({
    required this.label,
    required this.value,
    this.onTap,
    this.muted = false,
    this.ltr = false,
    this.trailing,
    super.key,
  });

  final String label;

  /// The current selection. Empty renders the muted placeholder styling, which
  /// is how the design distinguishes "nothing chosen yet" from a choice.
  final String value;

  final VoidCallback? onTap;

  /// True renders [value] in the secondary gray — the design's unfilled field.
  final bool muted;

  /// True for a value that is itself left-to-right, such as a listing URL. The
  /// chevron stays at the physical right either way.
  final bool ltr;

  /// Replaces the `⌄` chevron. Used by the city picker, which shows a pencil
  /// while it is being edited rather than an open-chevron.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final bool empty = value.trim().isEmpty;

    // An unfilled `.fld v` shows its own label in the muted grey.
    //
    // The reference never draws an empty one — every `.fld v` on the prototype is
    // prefilled — so this is the shape the design leaves unspecified. It is
    // [label], not an empty string, because a 48dp box holding nothing but a
    // chevron is indistinguishable from a field that failed to render, and three
    // of them in a row is a form that looks broken rather than unfinished.
    final String shown = empty ? label : value;

    final Widget field = Container(
      // Fills the cell it is given. A `Column` with `CrossAxisAlignment.start`
      // hands its children loose width, and a Container holding a `Row` with an
      // `Expanded` inside shrink-wraps to that Row's minimum — so without this
      // the design's full-width `.fld v` renders as a box as wide as its own
      // text, sitting in the middle of a wider column.
      width: double.infinity,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.inset),
      decoration: BoxDecoration(
        // `.fld.w` — the white variant. Every one of these sits inside a card
        // and holds a value rather than inviting typing, so it is white to
        // separate "this is set" from "this is a form to fill in".
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              shown,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: ltr ? TextDirection.ltr : null,
              style: TextStyle(
                fontSize: 13,
                height: 1.3,
                color: (empty || muted)
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
                fontWeight: (empty || muted)
                    ? FontWeight.w400
                    : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          trailing ??
              const Text(
                '⌄',
                // Pinned to LTR so the chevron is not mirrored into a different
                // glyph by the bidi algorithm. A `⌄` has no mirrored form, so
                // the override is what stops it becoming a mark that points the
                // wrong way under RTL.
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.2,
                  color: AppColors.textSecondary,
                ),
              ),
        ],
      ),
    );

    if (onTap == null) return field;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: field,
      ),
    );
  }
}

/// A [SelectField] that opens a sheet of [options] and reports the chosen index.
///
/// The design's `.fld v` + `⌄` fields are controls, not labels: on the
/// report-entry screen four of them hold a verdict that has to be picked from a
/// set, and the sheet is where that set is shown. A sheet rather than a
/// `DropdownButton` because Material's menu is a rounded white sheet with a
/// Material divider, and the reference's menus are full-bleed lists under a
/// centered title — the same sheet the centre picker and the date picker already
/// use in this app.
///
/// [onChanged] is not called when the same option is chosen again, so a
/// `ConsumerState` holding the selection is not rebuilt for no change.
class ChoiceField extends StatelessWidget {
  const ChoiceField({
    required this.label,
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
    super.key,
  });

  final String label;
  final List<String> options;

  /// -1 for nothing chosen yet, which renders the field in its muted state.
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final bool chosen = selectedIndex >= 0 && selectedIndex < options.length;
    return SelectField(
      label: label,
      value: chosen ? options[selectedIndex] : '',
      muted: !chosen,
      onTap: () => _pick(context),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final int? picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _ChoiceSheet(
        title: label,
        options: options,
        selectedIndex: selectedIndex,
      ),
    );
    if (picked == null || picked == selectedIndex) return;
    onChanged(picked);
  }
}

class _ChoiceSheet extends StatelessWidget {
  const _ChoiceSheet({
    required this.title,
    required this.options,
    required this.selectedIndex,
  });

  final String title;
  final List<String> options;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.title(15),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (BuildContext context, int index) => ListTile(
                title: Text(
                  options[index],
                  style: index == selectedIndex
                      ? AppText.title(14, color: AppColors.green)
                      : AppText.secondary(14),
                ),
                trailing: index == selectedIndex
                    ? const Icon(Icons.check, color: AppColors.green)
                    : null,
                onTap: () => Navigator.of(context).pop(index),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The design's `.seg`: a row of equal, tappable choices where the selected one
/// is light green with a green border and a green label.
///
/// A segmented control rather than a `DropdownButton` because the reference
/// shows every option at once — the design's whole point on these cards is that
/// the buyer or inspector can see the range of what "سليم" can mean before
/// choosing, and a collapsed menu hides exactly that.
class SegmentedChoice extends StatelessWidget {
  const SegmentedChoice({
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
    super.key,
  });

  final List<String> options;

  /// The index of the chosen option, or -1 for nothing chosen yet.
  final int selectedIndex;

  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (int i = 0; i < options.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _Segment(
              label: options[i],
              selected: i == selectedIndex,
              onTap: () => onChanged(i),
            ),
          ),
        ],
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.successSurface : AppColors.inputFill,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? AppColors.green : AppColors.cardBorder,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppText.pill(
              12,
              color: selected ? AppColors.green : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The design's photo slot: a flat gray square for an image that exists, and a
/// dashed-outline square for the one that would add the next.
///
/// [onTap] is what separates the two — a slot that can be pressed is an
/// "add" slot, so the caller does not have to remember to pass the right shape.
///
/// A taken photo replaces the gray with the image itself, and the label goes away
/// entirely: the design's `📸 صورة 1` is the *empty* state, and a filled slot
/// captioned `صورة 1` is a thumbnail with a redundant caption on top of it.
class PhotoSlot extends StatelessWidget {
  const PhotoSlot({
    required this.label,
    this.onTap,
    this.imageUrl,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;

  /// The photo's public URL, once one has been uploaded. Null for a slot with
  /// nothing in it, which is the state the design draws.
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final bool add = onTap != null;
    final String? url = imageUrl;

    final Widget content = url == null
        ? Text(
            label,
            textAlign: TextAlign.center,
            style: AppText.pill(11, color: AppColors.textSecondary),
          )
        : Image.network(
            url,
            fit: BoxFit.cover,
            // A broken URL must not leave a raw exception box in the middle of a
            // report the inspector is about to attest to; the slot falls back to
            // its empty state, which is a true statement about what is stored.
            errorBuilder: (_, _, _) => Text(
              label,
              textAlign: TextAlign.center,
              style: AppText.pill(11, color: AppColors.textSecondary),
            ),
            loadingBuilder: (
              BuildContext context,
              Widget child,
              ImageChunkEvent? progress,
            ) => progress == null
                ? child
                : const Center(
                    child: SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
          );

    final Widget slot = AspectRatio(
      aspectRatio: 1,
      child: url == null && add
          // Dashed rather than solid, and 1.5dp rather than 1dp: the design's
          // add-tile is the only dashed *box* in the app, and that is what
          // distinguishes "there is nothing here, add something" from "here is
          // a framed picture".
          ? DashedBorderBox(
              child: Container(
                width: double.infinity,
                alignment: Alignment.center,
                color: Colors.white,
                child: content,
              ),
            )
          : Container(
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: url == null ? AppColors.photoFill : null,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: content,
            ),
    );

    if (onTap == null) return slot;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: slot,
      ),
    );
  }
}

/// The market card's fee box: a large green figure over a tiny label, centred on
/// the light-green fill.
class FeeBadge extends StatelessWidget {
  const FeeBadge({required this.amount, required this.caption, super.key});

  /// The inspector's fee as the design writes it on this card: `+150`, without
  /// the currency, because the caption underneath carries the units.
  final String amount;

  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.row,
      ),
      decoration: BoxDecoration(
        color: AppColors.successSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            amount,
            style: AppText.title(22, color: AppColors.green).copyWith(
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(caption, style: AppText.pill(10, color: AppColors.green)),
        ],
      ),
    );
  }
}

/// A figure with a fill bar behind it, as the report's efficiency table draws
/// it: a fixed-width track, a green fill proportional to the score, and the
/// percentage beside it.
///
/// The track is a fixed 90dp because the design draws it that way and because a
/// bar that grows with the column is not a comparable bar — a 95% in a narrow
/// column and a 95% in a wide one have to be the same length to be read against
/// each other.
class EfficiencyBar extends StatelessWidget {
  const EfficiencyBar({
    required this.percent,
    required this.grade,
    this.warn = false,
    this.trackWidth = 90,
    super.key,
  });

  /// 0..100.
  final int percent;

  /// The design's own word for the figure: `(ممتاز)`, `(سليم)`, `(مقبول)`.
  final String grade;

  /// True for the one row the design paints orange — the 80% suspension.
  final bool warn;

  final double trackWidth;

  @override
  Widget build(BuildContext context) {
    final Color color = warn ? AppColors.warning : AppColors.green;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: SizedBox(
            width: trackWidth,
            height: 5,
            child: Stack(
              children: <Widget>[
                Container(color: AppColors.cardBorder),
                FractionallySizedBox(
                  // `direction: rtl` on the design's track, so the fill grows
                  // from the right. Reproduced by anchoring the fill's end to
                  // the start edge rather than by mirroring the widget, which
                  // would also mirror the grade beside it.
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: (percent / 100).clamp(0.0, 1.0),
                  child: Container(color: color),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '$percent% $grade',
          style: AppText.pill(12, color: color),
        ),
      ],
    );
  }
}

/// The buyer's invoice box: a hair-off-white surface with a border, holding a
/// heading row, the cost lines, a dashed rule and the total.
///
/// Off-white rather than the light green of the create screen's box, because the
/// two boxes say different things. On the create screen the light green is
/// "this is what it will cost you, roughly, and nothing is charged yet"; here the
/// centre is named and the total is a figure the buyer is being asked to approve,
/// so it reads as a document rather than a quote.
class InvoiceBox extends StatelessWidget {
  const InvoiceBox({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: child,
    );
  }
}

/// One line of a cost breakdown: a sentence on one side, a figure on the other.
///
/// Both sides flex. A `Row` hands non-flex children *unbounded* main-axis
/// width, and the design's labels are full sentences — "أتعاب المعاين (التنسيق
/// والجدولة)" — so an unconstrained one overflows the card instead of wrapping.
/// The figure gets the larger share because it is usually the shorter string.
class CostLine extends StatelessWidget {
  const CostLine({
    required this.label,
    required this.value,
    this.bullet = true,
    this.emphasise = false,
    this.valueColor,
    this.valueSize = 13,
    super.key,
  });

  final String label;
  final String value;

  /// The design's invoice lines are bulleted with a `•` and the create screen's
  /// are not; the two boxes differ by more than colour and this is the other
  /// difference.
  final bool bullet;

  final bool emphasise;
  final Color? valueColor;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Text(
              bullet ? '• $label' : label,
              style: emphasise
                  ? AppText.title(13, color: AppColors.greenDeep)
                  : TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.textPrimary,
                      fontWeight: emphasise
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppText.title(
                valueSize,
                color: valueColor ?? AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A state that has nothing to show: no request yet, no report yet, a list the
/// user has not filled.
///
/// Used by the tabs the reference does not draw and by every screen's empty
/// branch, so "nothing here yet" is one object rather than six near-identical
/// centre-aligned columns that drift apart.
class DesignEmpty extends StatelessWidget {
  const DesignEmpty({
    required this.title,
    this.body,
    this.action,
    super.key,
  });

  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppText.title(15),
          ),
          if (body case final String text when text.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppText.secondary(13),
            ),
          ],
          if (action != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            action!,
          ],
        ],
      ),
    );
  }
}

/// A load failure with a retry.
///
/// Every list in the app is a pure read, so retrying is always safe and a
/// permanent error page is never the right answer.
class DesignRetry extends StatelessWidget {
  const DesignRetry({
    required this.message,
    required this.actionLabel,
    required this.onRetry,
    super.key,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppText.secondary(13),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton(onPressed: onRetry, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

/// The design's `.fld`: a flat input with the hint *inside* it, not above.
///
/// A `TextFormField` with a Material `InputDecoration`, because the label has to
/// be able to sit above it as a [FieldLabel] — the reference never floats a label
/// into a field's border, and Material's floating label would put one there and
/// move the field's text when it takes focus. The error is rendered *below* the
/// field rather than inside it, for the same reason [CityPicker] reserves its
/// helper space: a row that changes height the moment it goes red shoves the rest
/// of a form down while the buyer is looking at it.
class DesignTextField extends StatelessWidget {
  const DesignTextField({
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.textInputAction,
    this.maxLines = 1,
    this.maxLength,
    this.enabled = true,
    this.ltr = false,
    super.key,
  });

  final TextEditingController controller;

  /// The reference's grey placeholder, shown inside the field while it is empty.
  final String? hintText;

  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final int maxLines;

  /// Sets the counter's reach, not the text: `maxLength` here is a *cap*, and the
  /// design shows no counter. See [showCounter]: the reference has no counters on
  /// any field, and a "12/1000" under a notes box is an instruction the design
  /// never gave.
  final int? maxLength;

  final bool enabled;

  /// True for a value that is itself left-to-right — a URL, a phone number. The
  /// field keeps the reference's shape; only the text's direction changes, because
  /// the bidi algorithm will otherwise lay out `https://haraj.com.sa/...` against
  /// an RTL paragraph and put the scheme at the wrong end.
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      textInputAction: textInputAction,
      maxLines: maxLines,
      minLines: maxLines,
      maxLength: maxLength,
      enabled: enabled,
      textDirection: ltr ? TextDirection.ltr : null,
      style: const TextStyle(
        fontSize: 13,
        height: 1.4,
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w400,
        ),
        filled: true,
        fillColor: AppColors.inputFill,
        isDense: true,
        // The reference's 12dp corners and 1dp border, on a fill that is the input
        // token rather than the theme's surface tint — these fields are grey on
        // purpose, to read as "fill this in" against the white card they sit in.
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.inset,
          vertical: AppSpacing.md,
        ),
        enabledBorder: _border(AppColors.cardBorder),
        focusedBorder: _border(AppColors.green),
        errorBorder: _border(AppColors.live),
        focusedErrorBorder: _border(AppColors.live),
        // Reserved whether or not there is an error, so the field does not change
        // height the moment it goes red.
        helperMaxLines: 2,
        errorMaxLines: 2,
        counterText: '',
        counterStyle: const TextStyle(fontSize: 0, height: 0),
      ),
    );
  }

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.md),
    borderSide: BorderSide(color: color),
  );
}

/// The dark header for a tab the reference's bar names but does not draw.
///
/// Shaped as the pushed-screen header rather than the tab header: these tabs are
/// the bottom half of the buyer's and inspector's bars, and there is nothing on
/// the reference to copy, so the one header the reference *does* define is reused
/// at the reduced weight a title needs. Without it these tabs would arrive as
/// Material `AppBar`s in a design that has no Material `AppBar` anywhere — which
/// is what "restyled, not left alone" has to rule out.
class ShellHeader extends StatelessWidget {
  const ShellHeader({required this.title, this.trailing, super.key});

  final String title;

  /// Optional pill at the far end, for a count or a status.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DarkHeader(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(title, style: AppText.onDark(19))),
          ?trailing,
        ],
      ),
    );
  }
}

/// One line of a detail list: a gray label at the start edge, the value filling
/// the rest.
///
/// Both sides flex for the same reason [CostLine] does. The labels in these lists
/// are sentences — `رقم جوال البائع` is fine, `رابط إعلان السيارة` is fine, but
/// `السعر المعتمد بعد اختيار المركز` would be given an unbounded width and
/// overflow rather than wrap.
class AccountRow extends StatelessWidget {
  const AccountRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.trailing,
    super.key,
  });

  final String label;
  final String value;
  final Color? valueColor;

  /// An optional control at the row's far end, past the value.
  ///
  /// For the one field on a detail list a person is allowed to change. The
  /// reference's `عرض كل` link is the same idea at the same size and in the same
  /// green, so an editable row and a navigable one look alike — which is correct:
  /// both are a small coloured verb at the end of a line of facts.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(label, style: AppText.secondary(13)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppText.title(
                13,
                color: valueColor ?? AppColors.textPrimary,
              ),
            ),
          ),
          if (trailing case final Widget action) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            action,
          ],
        ],
      ),
    );
  }
}
