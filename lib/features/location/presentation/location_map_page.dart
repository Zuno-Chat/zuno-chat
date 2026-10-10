import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/location/geo_uri.dart';
import '../../../core/location/maps_link.dart';
import '../../../core/navigation/zuno_links.dart';
import '../../../core/platform/platform_capabilities.dart';
import 'location_map_view.dart';

String? accuracyLabel(double? meters) {
  if (meters == null) return null;
  final rounded = meters.round();
  if (rounded < 1000) return 'about $rounded m';
  return 'about ${(meters / 1000).toStringAsFixed(1)} km';
}

Future<void> openInMaps(BuildContext context, GeoUri geo, MapsApp app) async {
  final messenger = ScaffoldMessenger.of(context);
  var opened = false;
  try {
    opened = await launchUrl(
      mapsLink(geo, app),
      mode: LaunchMode.externalApplication,
    );
  } catch (e, s) {
    if (!noAppOpensLink(e)) reportCaughtType('open in maps', e, s);
  }
  if (!opened) {
    messenger.showSnackBar(const SnackBar(content: Text('No maps app found')));
  }
}

class LocationMapPage extends ConsumerWidget {
  final GeoUri geo;
  final String senderName;
  final DateTime sentAt;

  const LocationMapPage({
    required this.geo,
    required this.senderName,
    required this.sentAt,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final accuracy = accuracyLabel(geo.uncertaintyMeters);
    void open() => openInMaps(
      context,
      geo,
      ref.read(platformCapabilitiesProvider).mapsApp,
    );
    final sent = MaterialLocalizations.of(context).formatMediumDate(sentAt);
    final time = TimeOfDay.fromDateTime(sentAt).format(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(senderName),
        actions: [
          IconButton(
            tooltip: 'Open in maps app',
            icon: const Icon(Icons.map_outlined),
            onPressed: open,
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: LocationMapView(geo: geo, interactive: true, zoom: 16),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: Card(
                color: theme.colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        geo.coordinatesLabel,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [?accuracy, '$sent · $time'].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: open,
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Open in maps app'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
