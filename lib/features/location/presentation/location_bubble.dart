import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/geo_uri.dart';
import '../../../core/location/map_tiles_provider.dart';
import 'location_map_view.dart';

const _previewAspectRatio = 16 / 10;

class LocationBubble extends ConsumerWidget {
  final GeoUri? geo;
  final double radius;
  final Widget trailing;
  final ValueChanged<GeoUri> onOpen;

  const LocationBubble({
    required this.geo,
    required this.radius,
    required this.trailing,
    required this.onOpen,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final geo = this.geo;
    final hasMap = ref.watch(mapTilesProvider).value != null;
    final label = geo == null || hasMap ? 'Location' : geo.coordinatesLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (geo != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onOpen(geo),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: AspectRatio(
                aspectRatio: _previewAspectRatio,
                child: LocationMapView(geo: geo, interactive: false),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(7, 6, 7, 3),
          child: Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        ),
      ],
    );
  }
}
