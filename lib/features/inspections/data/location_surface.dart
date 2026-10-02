import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Builds the map a custom centre's location is picked on.
///
/// A seam rather than a direct `FlutterMap` call for the same reason `PhotoPicker`
/// is an interface: `flutter_map` fetches raster tiles over HTTP, and `flutter test`
/// has no HTTP stack. A test that rendered the real map would fail on every tile
/// request — loudly, and in a way that has nothing to do with whatever the test was
/// asserting. Production binds [locationSurfaceProvider]; a test overrides it with
/// a stub that reports a point directly. No caller of the location picker knows
/// which it got.
typedef LocationSurfaceBuilder =
    Widget Function({required LatLng initial, required ValueChanged<LatLng> onPicked});

/// Where the map opens when nothing better is known.
///
/// Riyadh, because it is the largest city in `cities` and so the one a map opened
/// with nothing to go on is most likely to be *near*. The custom centre's own city
/// normally supplies a better anchor; this is the fallback for a city whose row has
/// no coordinate, not the normal case.
///
/// Zoomed to 13 rather than further out: Saudi is wide, and a view that fits the
/// whole country into a phone's width makes every individual shop the same three
/// pixels. 13 is roughly a district — the scale at which a person can tell whether
/// they are on the right road.
const LatLng kFallbackCentre = LatLng(24.7136, 46.6753);
const double kFallbackZoom = 13;

/// The tile template, and why it is a build-time constant.
///
/// Overridable with `--dart-define=MAP_TILE_URL=…` because the default is *not*
/// licensed for what this app would become. The OpenStreetMap Foundation's public
/// tile servers are free for light and evaluation use, and their usage policy
/// prohibits heavy or commercial use; a marketplace with paying users drawing a
/// map for every custom-centre booking is well past that. Point this at a provider
/// you hold a key for before shipping.
///
/// A build-time constant rather than a database row because it is a fact about the
/// deployment, not something the app's users or operators set — and putting it in
/// the database would make it changeable without a rebuild.
const String kMapTileUrlTemplate = String.fromEnvironment(
  'MAP_TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

/// The attribution a tile provider's terms require.
///
/// Shown whether or not a deployment swapped the tile source: attributing OSM when
/// the tiles came from somewhere else is not an error anyone wants to discover in a
/// compliance review, and the real requirement is that *some* attribution is shown.
///
/// A Dart constant rather than a localisation key, and that is not an oversight. It
/// is a proper noun in Latin script that the licence requires verbatim, so there is
/// no translation of it — and putting it in the ARB would mean either an Arabic
/// value that `localization_test` rightly flags as untranslated Latin, or a value
/// the check has to be taught to allowlist, which is one more place for a genuinely
/// stray fragment to hide.
const String kMapAttribution = '© OpenStreetMap contributors';

/// The production surface: an interactive map that reports the tapped point.
Widget systemLocationSurface({
  required LatLng initial,
  required ValueChanged<LatLng> onPicked,
}) => _InteractiveMap(initial: initial, onPicked: onPicked);

/// Stateful because the pin has to follow the taps.
///
/// The alternative — holding the point in the surface's caller and rebuilding this
/// whole widget on every tap — would rebuild the map (and therefore its tile cache)
/// each time, which is the expensive thing on the screen.
class _InteractiveMap extends StatefulWidget {
  const _InteractiveMap({required this.initial, required this.onPicked});

  final LatLng initial;
  final ValueChanged<LatLng> onPicked;

  @override
  State<_InteractiveMap> createState() => _InteractiveMapState();
}

class _InteractiveMapState extends State<_InteractiveMap> {
  late LatLng _point = widget.initial;

  void _onTap(LatLng point) {
    setState(() => _point = point);
    // Reported *after* the rebuild is scheduled, not instead of it: the caller
    // writes the coordinate into a form field, and doing that before the pin moved
    // would show a new number under a pin that has not moved yet.
    widget.onPicked(point);
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: widget.initial,
        initialZoom: kFallbackZoom,
        onTap: (TapPosition _, LatLng point) => _onTap(point),
      ),
      children: <Widget>[
        TileLayer(urlTemplate: kMapTileUrlTemplate),
        MarkerLayer(
          markers: <Marker>[
            Marker(point: _point, width: 48, height: 48, child: const _CentrePin()),
          ],
        ),
      ],
    );
  }
}

/// The pin, drawn rather than iconed.
///
/// The design uses no icon library anywhere, so this is a painted shape: a filled
/// circle inside a white ring, legible against both pale desert and dark asphalt,
/// and needing no asset to be added to the bundle.
class _CentrePin extends StatelessWidget {
  const _CentrePin();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.topCenter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0xFF16A05F),
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[BoxShadow(color: Color(0x33000000), blurRadius: 6)],
        ),
        child: SizedBox(
          width: 18,
          height: 18,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFFFFFFFF),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// `24.7136, 46.6753` — the picked point, for the person to recognise.
///
/// Four decimal places is about 11 metres, which is finer than the entrance of any
/// building and so not a claim to precision anyone can act on; five would be false
/// precision over a phone GPS reading that is itself worth a few metres. The figure
/// is shown so the person choosing can confirm the pin is where they meant, not so
/// they can read it back into a form.
String formatLatLng(LatLng point) =>
    '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';