import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/location/geo_uri.dart';
import '../../../core/location/map_tiles_provider.dart';

const _pinSize = 40.0;
const _maxTileZoom = 19.0;

class LocationMapView extends ConsumerWidget {
  final GeoUri geo;
  final bool interactive;
  final double zoom;

  const LocationMapView({
    required this.geo,
    required this.interactive,
    this.zoom = 15,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiles = ref.watch(mapTilesProvider).value;
    if (tiles == null) return _GridFallback(geo: geo);

    final attribution = tiles.attribution;
    final colors = Theme.of(context).colorScheme;
    final point = LatLng(geo.latitude, geo.longitude);
    return IgnorePointer(
      ignoring: !interactive,
      child: FlutterMap(
        options: MapOptions(
          initialCenter: point,
          initialZoom: zoom,
          maxZoom: _maxTileZoom,
          backgroundColor: colors.surfaceContainerHighest,
          interactionOptions: InteractionOptions(
            flags: interactive
                ? InteractiveFlag.all & ~InteractiveFlag.rotate
                : InteractiveFlag.none,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: tiles.urlTemplate,
            tileProvider: tiles.tileProvider,
            userAgentPackageName: 'im.zuno.chat',
            maxNativeZoom: _maxTileZoom.toInt(),
            panBuffer: 0,
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: point,
                width: _pinSize,
                height: _pinSize,
                alignment: Alignment.topCenter,
                child: const _LocationPin(),
              ),
            ],
          ),
          if (interactive && attribution != null) _Attribution(attribution),
        ],
      ),
    );
  }
}

class _Attribution extends StatelessWidget {
  final String credit;

  const _Attribution(this.credit);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DefaultTextStyle(
      style: TextStyle(
        fontSize: 10,
        color: colors.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      child: SimpleAttributionWidget(
        alignment: Alignment.topRight,
        backgroundColor: colors.surface.withValues(alpha: 0.5),
        source: Text(credit),
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
      painter: _GridPainter(
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

class _GridPainter extends CustomPainter {
  final Color background;
  final Color line;

  const _GridPainter({required this.background, required this.line});

  static const _spacing = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var x = _spacing; x < size.width; x += _spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = _spacing; y < size.height; y += _spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.background != background || old.line != line;
}
