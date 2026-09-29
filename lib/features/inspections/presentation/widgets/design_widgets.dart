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

import 'package:flutter/material.dart';

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
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.xl,
    ),
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

/// A pill or badge.
///
/// The design uses three variants and they are not interchangeable — a light-green
/// pill on white, a dark-green pill on a dark header, and a pale-orange badge — so
/// they are named rather than left to a `color` parameter, which is how a
/// "light-green fill" ends up with the wrong text contrast.
enum PillTone { success, onDark, warning, neutral }

class AppPill extends StatelessWidget {
  const AppPill({
    required this.label,
    this.tone = PillTone.success,
    this.icon,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    super.key,
  });

  final String label;
  final PillTone tone;
  final IconData? icon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color foreground) = switch (tone) {
      PillTone.success => (AppColors.successSurface, AppColors.greenDeep),
      PillTone.onDark => (AppColors.darkBadge, AppColors.darkBadgeOn),
      PillTone.warning => (
        AppColors.warning.withValues(alpha: 0.14),
        AppColors.warning,
      ),
      PillTone.neutral => (AppColors.inputFill, AppColors.textSecondary),
    };

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: tone == PillTone.success
            ? Border.all(color: AppColors.successBorder)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: AppSpacing.xs),
          ],
          // The design's pills carry their own emoji (`📍`, `🔴`, `🔒`) inside the
          // label string, so the text is not padded with a separate icon here.
          Flexible(
            child: Text(
              label,
              style: AppText.pill(12, color: foreground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
      child: Text(text, style: AppText.title(14, color: color)),
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
    final Widget row = Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
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
                    style: AppText.onDark(16),
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

  @override
  Widget build(BuildContext context) {
    return Container(
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
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: AppText.title(15, color: titleColor),
                ),
              ),
              if (trailingLabel != null)
                Text(
                  trailingLabel!,
                  style: AppText.pill(11, color: AppColors.green),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const DashedDivider(),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}
