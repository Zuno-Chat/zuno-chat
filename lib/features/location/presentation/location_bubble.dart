import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/location/geo_uri.dart';
import '../../../core/location/map_tiles_provider.dart';
import 'location_map_view.dart';
import 'map_parts.dart';

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
    final label = geo == null || hasMap
        ? context.l10n.locationBubbleLabel
        : geo.coordinatesLabel;
    return MapPreviewFrame(
      preview: geo == null
          ? null
          : LocationMapView(geo: geo, interactive: false),
      radius: radius,
      onTap: geo == null ? null : () => onOpen(geo),
      icon: Icons.location_on_outlined,
      caption: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing,
    );
  }
}
