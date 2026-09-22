import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/location/current_position.dart';
import '../../../core/location/geo_uri.dart';
import 'location_map_page.dart';
import 'location_map_view.dart';

Future<GeoUri?> showLocationShareSheet(
  BuildContext context, {
  Future<LocationFix> Function()? find,
}) => showModalBottomSheet<GeoUri>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _LocationShareSheet(find: find ?? findCurrentLocation),
);

class _LocationShareSheet extends StatefulWidget {
  final Future<LocationFix> Function() find;

  const _LocationShareSheet({required this.find});

  @override
  State<_LocationShareSheet> createState() => _LocationShareSheetState();
}

class _LocationShareSheetState extends State<_LocationShareSheet> {
  LocationFix? _fix;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() => _fix = null);
    final fix = await widget.find();
    if (mounted) setState(() => _fix = fix);
  }

  @override
  Widget build(BuildContext context) {
    final fix = _fix;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Your location',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            switch (fix) {
              null => const _Finding(),
              LocationFound() => _Found(fix: fix),
              LocationFailed() => _Failed(reason: fix.reason, retry: _locate),
            },
          ],
        ),
      ),
    );
  }
}

class _Finding extends StatelessWidget {
  const _Finding();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 12),
        Flexible(child: Text('Finding your location…')),
      ],
    ),
  );
}

class _Found extends StatelessWidget {
  final LocationFound fix;

  const _Found({required this.fix});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accuracy = accuracyLabel(fix.geo.uncertaintyMeters);
    final detail = [
      if (fix.approximate) 'Approximate location',
      ?accuracy,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: LocationMapView(geo: fix.geo, interactive: false),
          ),
        ),
        const SizedBox(height: 12),
        Text(fix.geo.coordinatesLabel),
        if (detail.isNotEmpty)
          Text(
            detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(fix.geo),
          child: const Text('Send location'),
        ),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  final LocationFailure reason;
  final VoidCallback retry;

  const _Failed({required this.reason, required this.retry});

  @override
  Widget build(BuildContext context) {
    final (message, settings) = switch (reason) {
      LocationFailure.servicesOff => (
        'Location is off. Turn it on to share where you are.',
        Geolocator.openLocationSettings,
      ),
      LocationFailure.denied => (
        'Allow location access to share where you are.',
        null,
      ),
      LocationFailure.deniedForever => (
        'Location access is blocked. Allow it in Settings.',
        Geolocator.openAppSettings,
      ),
      LocationFailure.unavailable => ('Could not find your location.', null),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (settings != null)
              TextButton(
                onPressed: settings,
                child: const Text('Open settings'),
              ),
            FilledButton(onPressed: retry, child: const Text('Try again')),
          ],
        ),
      ],
    );
  }
}
