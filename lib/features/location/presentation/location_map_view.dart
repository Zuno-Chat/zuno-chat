import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/location/geo_uri.dart';
import '../../../core/location/map_tiles_provider.dart';
import 'map_parts.dart';

const _pinSize = 40.0;

class LocationMapView extends ConsumerWidget {
  final GeoUri geo;
  final bool interactive;
  final double zoom;
  final bool persistTiles;

  const LocationMapView({
    required this.geo,
    required this.interactive,
    this.zoom = 15,
    this.persistTiles = true,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiles = ref.watch(mapTilesProvider).value;
    if (tiles == null) return _GridFallback(geo: geo);
    return _TiledMap(
      tiles: tiles,
      point: LatLng(geo.latitude, geo.longitude),
      interactive: interactive,
      zoom: zoom,
      persistTiles: persistTiles,
    );
  }
}

class _TiledMap extends StatefulWidget {
  final MapTiles tiles;
  final LatLng point;
  final bool interactive;
  final double zoom;
  final bool persistTiles;

  const _TiledMap({
    required this.tiles,
    required this.point,
    required this.interactive,
    required this.zoom,
    required this.persistTiles,
  });

  @override
  State<_TiledMap> createState() => _TiledMapState();
}

class _TiledMapState extends State<_TiledMap> {
  final _map = MapController();
  late final LatLng _start = widget.point;
  late LatLngBounds _reach = neighbourhoodBounds([_start]);
  var _ready = false;

  @override
  void didUpdateWidget(_TiledMap old) {
    super.didUpdateWidget(old);
    if (old.point == widget.point) return;
    _reach = grownNeighbourhood(_reach, widget.point);
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _onMapReady() {
    _ready = true;
    _follow();
  }

  void _follow() {
    if (!mounted || !_ready) return;
    final camera = _map.camera;
    if (camera.center != widget.point) _map.move(widget.point, camera.zoom);
  }

  @override
  Widget build(BuildContext context) {
    final tiles = widget.tiles;
    final interactive = widget.interactive;
    final attribution = tiles.attribution;
    final colors = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: !interactive,
      child: FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: _start,
          initialZoom: widget.zoom,
          minZoom: interactive ? minFullMapZoom : null,
          maxZoom: maxTileZoom,
          cameraConstraint: interactive
              ? CameraConstraint.contain(bounds: _reach)
              : const CameraConstraint.unconstrained(),
          backgroundColor: colors.surfaceContainerHighest,
          interactionOptions: InteractionOptions(
            flags: interactive
                ? InteractiveFlag.all & ~InteractiveFlag.rotate
                : InteractiveFlag.none,
          ),
          onMapReady: _onMapReady,
        ),
        children: [
          TileLayer(
            urlTemplate: tiles.urlTemplate,
            tileProvider: widget.persistTiles
                ? tiles.tileProvider
                : tiles.ephemeralTileProvider,
            userAgentPackageName: 'im.zuno.chat',
            maxNativeZoom: maxTileZoom.toInt(),
            panBuffer: 0,
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: widget.point,
                width: _pinSize,
                height: _pinSize,
                alignment: Alignment.topCenter,
                child: const _LocationPin(),
              ),
            ],
          ),
          if (interactive && attribution != null) MapAttribution(attribution),
        ],
      ),
    );
  }
}

class _LocationPin extends StatelessWidget {
  const _LocationPin();

  @override
  Widget build(BuildContext context) => Icon(
    Icons.location_on,
    size: _pinSize,
    color: Theme.of(context).colorScheme.primary,
    shadows: const [Shadow(blurRadius: 4, color: Colors.black38)],
  );
}

class _GridFallback extends StatelessWidget {
  final GeoUri geo;

  const _GridFallback({required this.geo});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: MapGridPainter(
        background: colors.surfaceContainerHighest,
        line: colors.outlineVariant,
      ),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.only(bottom: _pinSize),
          child: _LocationPin(),
        ),
      ),
    );
  }
}
