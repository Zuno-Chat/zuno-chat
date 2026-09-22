import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/location/geo_uri.dart';
import 'location_map_view.dart';

String? accuracyLabel(double? meters) {
  if (meters == null) return null;
  if (meters < 1000) return 'about ${meters.round()} m';
  return 'about ${(meters / 1000).toStringAsFixed(1)} km';
}

Future<void> openInMaps(BuildContext context, GeoUri geo) async {
  final messenger = ScaffoldMessenger.of(context);
  var opened = false;
  try {
    opened = await launchUrl(
      geo.externalMapsUri,
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {}
  if (!opened) {
    messenger.showSnackBar(const SnackBar(content: Text('No maps app found')));
  }
}

class LocationMapPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accuracy = accuracyLabel(geo.uncertaintyMeters);
    final sent = MaterialLocalizations.of(context).formatMediumDate(sentAt);
    final time = TimeOfDay.fromDateTime(sentAt).format(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(senderName),
        actions: [
          IconButton(
            tooltip: 'Open in maps app',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => openInMaps(context, geo),
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
                        onPressed: () => openInMaps(context, geo),
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
