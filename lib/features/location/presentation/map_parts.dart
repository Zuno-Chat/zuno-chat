import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

const maxTileZoom = 19.0;
const minFullMapZoom = 12.0;

const _panRadiusMeters = 10000.0;
const _metersPerDegreeLatitude = 111320.0;
const _maxMercatorLatitude = 85.0;

LatLngBounds neighbourhoodBounds(Iterable<LatLng> points) =>
    points.map(_neighbourhoodOf).reduce(_union);

LatLngBounds grownNeighbourhood(LatLngBounds? reach, LatLng point) {
  final box = _neighbourhoodOf(point);
  if (reach == null) return box;
  return reach.containsBounds(box) ? reach : _union(reach, box);
}

LatLngBounds regionOf(Iterable<LatLngBounds> boxes) => boxes.reduce(_union);

double zoomToFit(
  LatLngBounds bounds,
  Size viewport, {
  EdgeInsets padding = EdgeInsets.zero,
}) {
  if (viewport.isEmpty || !viewport.isFinite) return minFullMapZoom;
  return CameraFit.bounds(
        bounds: bounds,
        padding: padding,
        maxZoom: maxTileZoom,
      )
      .fit(
        MapCamera(
          crs: const Epsg3857(),
          center: bounds.center,
          zoom: 0,
          rotation: 0,
          nonRotatedSize: viewport,
        ),
      )
      .zoom;
}

LatLngBounds _neighbourhoodOf(LatLng point) {
  const latSpan = _panRadiusMeters / _metersPerDegreeLatitude;
  final latitude = point.latitude.clamp(
    -_maxMercatorLatitude + latSpan,
    _maxMercatorLatitude - latSpan,
  );
  final lonSpan = latSpan / math.cos(latitude * math.pi / 180);
  return LatLngBounds.unsafe(
    north: latitude + latSpan,
    south: latitude - latSpan,
    east: math.min(point.longitude + lonSpan, 180),
    west: math.max(point.longitude - lonSpan, -180),
  );
}

LatLngBounds _union(LatLngBounds a, LatLngBounds b) => LatLngBounds.unsafe(
  north: math.max(a.north, b.north),
  south: math.min(a.south, b.south),
  east: math.max(a.east, b.east),
  west: math.min(a.west, b.west),
);

class MapAttribution extends StatelessWidget {
  final String credit;

  const MapAttribution(this.credit, {super.key});

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

class MapGrid extends StatelessWidget {
  final Widget? child;

  const MapGrid({this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _MapGridPainter(
        background: colors.surfaceContainerHighest,
        line: colors.outlineVariant,
      ),
      child: child,
    );
  }
}

class _MapGridPainter extends CustomPainter {
  final Color background;
  final Color line;

  const _MapGridPainter({required this.background, required this.line});

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
  bool shouldRepaint(_MapGridPainter old) =>
      old.background != background || old.line != line;
}

class MapPreviewFrame extends StatelessWidget {
  final Widget? preview;
  final double radius;
  final VoidCallback? onTap;
  final IconData icon;
  final Widget caption;
  final Widget trailing;

  const MapPreviewFrame({
    this.preview,
    required this.radius,
    this.onTap,
    required this.icon,
    required this.caption,
    required this.trailing,
    super.key,
  });

  static const _aspectRatio = 16 / 10;

  @override
  Widget build(BuildContext context) {
    final preview = this.preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (preview != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: AspectRatio(aspectRatio: _aspectRatio, child: preview),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(7, 6, 7, 3),
          child: Row(
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 4),
              Expanded(child: caption),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        ),
      ],
    );
  }
}
