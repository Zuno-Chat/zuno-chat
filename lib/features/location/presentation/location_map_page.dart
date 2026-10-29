import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/format/date_labels.dart';
import '../../../core/format/human_units.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/location/geo_uri.dart';
import '../../../core/location/maps_link.dart';
import '../../../core/navigation/zuno_links.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/ui/notice.dart';
import 'location_map_view.dart';

String? accuracyLabel(AppLocalizations l10n, double? meters) {
  if (meters == null) return null;
  final rounded = meters.round();
  if (rounded < 1000) return l10n.locationAccuracyMeters(rounded);
  return l10n.locationAccuracyKilometers(meters / 1000);
}

Future<void> openInMaps(BuildContext context, GeoUri geo, MapsApp app) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  var opened = false;
  try {
    opened = await launchUrl(
      mapsLink(geo, app),
      mode: LaunchMode.externalApplication,
    );
  } catch (e, s) {
    if (!noAppOpensLink(e)) reportCaughtType('open in maps', e, s);
  }
  if (!opened) messenger.say(l10n.locationNoMapsApp);
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
    final l10n = context.l10n;
    final accuracy = accuracyLabel(l10n, geo.uncertaintyMeters);
    void open() => openInMaps(
      context,
      geo,
      ref.read(platformCapabilitiesProvider).mapsApp,
    );
    final sent = DateLabels.of(context).dateTime(sentAt);
    return Scaffold(
      appBar: AppBar(
        title: Text(senderName),
        actions: [
          IconButton(
            tooltip: l10n.locationOpenInMaps,
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
                        joinDetails([?accuracy, sent]),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: open,
                        icon: const Icon(Icons.map_outlined),
                        label: Text(l10n.locationOpenInMaps),
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
