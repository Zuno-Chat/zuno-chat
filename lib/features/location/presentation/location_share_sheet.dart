import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/location/current_position.dart';
import '../../../core/location/geo_uri.dart';
import '../../../core/location/live_location_availability.dart';
import '../../../core/location/live_location_protocol.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/push/background_sync/background_sync_service.dart';
import '../../../core/ui/sheet.dart';
import 'location_failure_text.dart';
import 'location_map_page.dart';
import 'location_map_view.dart';

sealed class LocationShareChoice {
  const LocationShareChoice();
}

final class SendPin extends LocationShareChoice {
  final GeoUri geo;

  const SendPin(this.geo);

  @override
  bool operator ==(Object other) => other is SendPin && other.geo == geo;

  @override
  int get hashCode => geo.hashCode;
}

final class ShareLive extends LocationShareChoice {
  final LivePosition first;
  final LiveLocationDuration duration;

  const ShareLive(this.first, this.duration);

  @override
  bool operator ==(Object other) =>
      other is ShareLive && other.first == first && other.duration == duration;

  @override
  int get hashCode => Object.hash(first, duration);
}

const _previewShare = 0.3;

Future<LocationShareChoice?> showLocationShareSheet(
  BuildContext context, {
  Future<LocationFix> Function()? find,
  LiveLocationAvailability liveLocation = LiveLocationAvailability.unavailable,
  bool inChat = false,
  Future<bool> Function()? runsUnrestricted,
  Future<void> Function()? allowUnrestricted,
}) => showSheet<LocationShareChoice>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _LocationShareSheet(
    find: find ?? findCurrentLocation,
    liveLocation: liveLocation,
    inChat: inChat,
    runsUnrestricted:
        runsUnrestricted ??
        BackgroundSyncService.instance.isIgnoringBatteryOptimizations,
    allowUnrestricted:
        allowUnrestricted ??
        BackgroundSyncService.instance.requestIgnoreBatteryOptimizations,
  ),
);

class _LocationShareSheet extends StatefulWidget {
  final Future<LocationFix> Function() find;
  final LiveLocationAvailability liveLocation;
  final bool inChat;
  final Future<bool> Function() runsUnrestricted;
  final Future<void> Function() allowUnrestricted;

  const _LocationShareSheet({
    required this.find,
    required this.liveLocation,
    required this.inChat,
    required this.runsUnrestricted,
    required this.allowUnrestricted,
  });

  @override
  State<_LocationShareSheet> createState() => _LocationShareSheetState();
}

class _LocationShareSheetState extends State<_LocationShareSheet> {
  LocationFix? _fix;
  bool _choosingDuration = false;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() {
      _fix = null;
      _choosingDuration = false;
    });
    final fix = await widget.find();
    if (mounted) setState(() => _fix = fix);
  }

  @override
  Widget build(BuildContext context) {
    final fix = _fix;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _choosingDuration
                  ? context.l10n.locationShareLive
                  : context.l10n.locationYourLocation,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            switch (fix) {
              null => const _Finding(),
              LocationFound() when _choosingDuration => _LiveDuration(
                fix: fix,
                inChat: widget.inChat,
                runsUnrestricted: widget.runsUnrestricted,
                allowUnrestricted: widget.allowUnrestricted,
                onBack: () => setState(() => _choosingDuration = false),
              ),
              LocationFound() => _Found(
                fix: fix,
                liveLocation: widget.liveLocation,
                inChat: widget.inChat,
                onShareLive: () => setState(() => _choosingDuration = true),
              ),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Flexible(child: Text(context.l10n.locationFinding)),
      ],
    ),
  );
}

class _Found extends StatelessWidget {
  final LocationFound fix;
  final LiveLocationAvailability liveLocation;
  final bool inChat;
  final VoidCallback onShareLive;

  const _Found({
    required this.fix,
    required this.liveLocation,
    required this.inChat,
    required this.onShareLive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final accuracy = accuracyLabel(l10n, fix.geo.uncertaintyMeters);
    final detail = [
      if (fix.approximate) l10n.locationApproximate,
      ?accuracy,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * _previewShare,
            ),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: LocationMapView(geo: fix.geo, interactive: false),
            ),
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
          onPressed: () => Navigator.of(context).pop(SendPin(fix.geo)),
          child: Text(l10n.locationSend),
        ),
        if (liveLocation != LiveLocationAvailability.unavailable) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: liveLocation == LiveLocationAvailability.available
                ? onShareLive
                : null,
            icon: const Icon(Icons.share_location_outlined),
            label: Text(l10n.locationShareLive),
          ),
          if (_unavailableReason(l10n, liveLocation, inChat: inChat)
              case final reason?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                reason,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

String? _unavailableReason(
  AppLocalizations l10n,
  LiveLocationAvailability availability, {
  required bool inChat,
}) => switch (availability) {
  LiveLocationAvailability.notAllowed =>
    inChat ? l10n.locationLiveNotInChat : l10n.locationLiveNeedsAdmin,
  LiveLocationAvailability.alreadySharing => l10n.locationAlreadySharing,
  LiveLocationAvailability.unavailable ||
  LiveLocationAvailability.available => null,
};

class _LiveDuration extends StatefulWidget {
  final LocationFound fix;
  final bool inChat;
  final Future<bool> Function() runsUnrestricted;
  final Future<void> Function() allowUnrestricted;
  final VoidCallback onBack;

  const _LiveDuration({
    required this.fix,
    required this.inChat,
    required this.runsUnrestricted,
    required this.allowUnrestricted,
    required this.onBack,
  });

  @override
  State<_LiveDuration> createState() => _LiveDurationState();
}

class _LiveDurationState extends State<_LiveDuration> {
  LiveLocationDuration _duration = LiveLocationDuration.quarterHour;
  bool? _unrestricted;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _checkUnrestricted);
    _checkUnrestricted();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _checkUnrestricted() async {
    bool unrestricted;
    try {
      unrestricted = await widget.runsUnrestricted();
    } catch (error, stack) {
      reportCaught('battery exemption check', error, stack);
      unrestricted = true;
    }
    if (mounted) setState(() => _unrestricted = unrestricted);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.inChat
              ? l10n.locationLiveAudienceChat
              : l10n.locationLiveAudienceRoom,
        ),
        if (widget.fix.approximate)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.locationLiveApproximate,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (_unrestricted == false) ...[
          const SizedBox(height: 8),
          Text(
            l10n.locationAndroidMayPause,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: widget.allowUnrestricted,
              child: Text(l10n.locationRunUnrestricted),
            ),
          ),
        ],
        const SizedBox(height: 8),
        RadioGroup<LiveLocationDuration>(
          groupValue: _duration,
          onChanged: (duration) => setState(() => _duration = duration!),
          child: Column(
            children: [
              for (final duration in LiveLocationDuration.values)
                RadioListTile<LiveLocationDuration>(
                  title: Text(_durationText(l10n, duration)),
                  value: duration,
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: widget.onBack,
              child: Text(l10n.locationBack),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                ShareLive(
                  LivePosition(geo: widget.fix.geo, at: widget.fix.at),
                  _duration,
                ),
              ),
              child: Text(l10n.locationStartSharing),
            ),
          ],
        ),
      ],
    );
  }
}

String _durationText(AppLocalizations l10n, LiveLocationDuration duration) =>
    duration.duration.inMinutes < 60
    ? l10n.locationDurationMinutes(duration.duration.inMinutes)
    : l10n.locationDurationHours(duration.duration.inHours);

class _Failed extends ConsumerWidget {
  final LocationFailure reason;
  final VoidCallback retry;

  const _Failed({required this.reason, required this.retry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final servicesSettings = ref
        .watch(platformCapabilitiesProvider)
        .locationServicesSettings;
    final copy = locationFailureCopy(
      l10n,
      reason,
      goal: LocationGoal.shareWhereYouAre,
      servicesSettings: servicesSettings,
    );
    final settings = copy.openSettings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(copy.message),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (settings != null)
              TextButton(
                onPressed: settings,
                child: Text(l10n.commonOpenSettings),
              ),
            FilledButton(onPressed: retry, child: Text(l10n.commonTryAgain)),
          ],
        ),
      ],
    );
  }
}
