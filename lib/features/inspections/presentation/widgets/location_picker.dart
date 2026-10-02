import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../application/inspection_controller.dart';
import '../../data/location_surface.dart';
import 'design_widgets.dart';

/// Opens the map so a person can drop a pin on the inspection centre.
///
/// Returns the point, or null if the sheet was dismissed — including dismissing it
/// after moving the pin, which is deliberate: backing out of a picker should
/// discard the pick, not commit a point the person was still trying to adjust.
///
/// [initial] is where the map opens, which callers should set to the request's own
/// city rather than the national fallback. [selected] is the pin to start with, so
/// re-opening a picker on an existing centre shows the pin where it already is
/// instead of the city centre, and the person can see what they are about to move.
Future<LatLng?> showLocationSheet(
  BuildContext context, {
  required LatLng initial,
  LatLng? selected,
}) => showModalBottomSheet<LatLng>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (BuildContext sheetContext) => _LocationSheet(
    initial: selected ?? initial,
  ),
);

class _LocationSheet extends ConsumerStatefulWidget {
  const _LocationSheet({required this.initial});

  final LatLng initial;

  @override
  ConsumerState<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends ConsumerState<_LocationSheet> {
  late LatLng _point = widget.initial;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Padding(
      // The keyboard cannot reach this sheet — it has no text field — but the sheet
      // still has to clear the home indicator, or the confirm button sits under it.
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.locationSheetTitle,
                    style: AppText.title(16),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l10n.locationSheetHint,
                    style: AppText.secondary(13),
                  ),
                ],
              ),
            ),
            // A fixed height rather than a flexible one: the map needs a known size
            // to lay out its tiles, and `Expanded` inside a `mainAxisSize.min` sheet
            // has no bounded height to divide. 60% of the screen is enough to pan
            // across a district and short enough to leave the confirm button and
            // the selected coordinate visible without scrolling.
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.55,
              child: ref.watch(
                locationSurfaceProvider,
              )(
                initial: widget.initial,
                onPicked: (LatLng point) => setState(() => _point = point),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: <Widget>[
                  // The coordinate is shown so the person can confirm the pin went
                  // where they meant. An inspector who cannot tell a Dammam pin from
                  // a Riyadh one is being asked to trust a shape.
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      formatLatLng(_point),
                      style: AppText.secondary(14),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // No SizedBox around it: the theme's button `minimumSize` is
                  // already `buttonHeightTall`, and a second explicit height here
                  // would be a second number to keep in step with the design.
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_point),
                    child: Text(l10n.createSubmit),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    kMapAttribution,
                    textAlign: TextAlign.center,
                    style: AppText.secondary(
                      11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The field that opens [showLocationSheet] — a `SelectField` showing either the
/// coordinate or the design's muted "tap to set" placeholder.
///
/// A field rather than an always-visible map because the create-request form is
/// already four cards tall and the inspector's booking box has a day, a time and a
/// centre already. An inline map on both would push the confirm button off a phone
/// screen, which is the one thing a booking form must not do.
///
/// It takes the point rather than the city so the caller owns the anchor: the buyer
/// passes the request's city, the inspector passes the buyer's suggested pin when
/// there is one, and both fall back to [kFallbackCentre] rather than each
/// re-deciding what the default should be.
class LocationField extends StatelessWidget {
  const LocationField({
    required this.value,
    required this.onChanged,
    required this.initial,
    super.key,
  });

  /// The chosen point, or null when nothing has been chosen.
  final LatLng? value;

  final ValueChanged<LatLng> onChanged;

  /// Where the map opens when [value] is null.
  final LatLng initial;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final LatLng? point = value;

    return SelectField(
      label: l10n.customCentreLocationLabel,
      // The coordinate is Latin digits and commas, so the field's own direction is
      // forced LTR. Inherited RTL it would render as "46.6753, 24.7136" reordered,
      // which is a valid-looking but wrong coordinate.
      ltr: true,
      muted: point == null,
      value: point == null
          ? l10n.customCentreLocationEmpty
          : formatLatLng(point),
      onTap: () async {
        final LatLng? picked = await showLocationSheet(
          context,
          initial: initial,
          selected: point,
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}
