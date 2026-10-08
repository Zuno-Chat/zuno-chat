import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';

import '../../../core/location/current_position.dart';
import '../../../core/location/geo_uri.dart';
import '../../../core/location/live_location_sharing.dart';
import '../../../core/location/live_location_viewing.dart';
import '../../../core/location/map_tiles_provider.dart';
import '../../../core/location/own_location_tracker.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/ui/visible_in_front.dart';
import 'live_location_clock.dart';
import 'live_location_text.dart';
import 'live_location_watch_scope.dart';
import 'location_failure_text.dart';
import 'location_map_page.dart';
import 'map_parts.dart';

const _markerSize = 44.0;
const _ownDotSize = 22.0;
const _focusZoom = 16.0;

class LiveLocationMapPage extends ConsumerStatefulWidget {
  final Room room;
  final String? focus;

  const LiveLocationMapPage({required this.room, this.focus, super.key});

  @override
  ConsumerState<LiveLocationMapPage> createState() =>
      _LiveLocationMapPageState();
}

class _LiveLocationMapPageState extends ConsumerState<LiveLocationMapPage> {
  late String? _focus = widget.focus;
  var _focusRequests = 0;

  void _focusOn(String userId) => setState(() {
    _focus = userId;
    _focusRequests++;
  });

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final shares = ref.watch(liveSharesProvider(room.id));
    final now = watchLiveNow(ref);
    return LiveLocationWatchScope(
      roomId: room.id,
      child: Scaffold(
        appBar: AppBar(title: Text(roomTitle(room))),
        body: shares.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Nobody is sharing live location here right now.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: shares.any((share) => share.position != null)
                        ? _LiveMap(
                            room: room,
                            shares: shares,
                            now: now,
                            focus: _focus,
                            focusRequests: _focusRequests,
                            canShowMe: !shares.any(
                              (share) => share.fromThisDevice,
                            ),
                          )
                        : const _WaitingForLocation(),
                  ),
                  _Sharers(
                    room: room,
                    shares: shares,
                    now: now,
                    onFocus: _focusOn,
                  ),
                ],
              ),
      ),
    );
  }
}

class _LiveMap extends ConsumerStatefulWidget {
  final Room room;
  final List<LiveShareView> shares;
  final DateTime now;
  final String? focus;
  final int focusRequests;
  final bool canShowMe;

  const _LiveMap({
    required this.room,
    required this.shares,
    required this.now,
    required this.focus,
    required this.focusRequests,
    required this.canShowMe,
  });

  @override
  ConsumerState<_LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends ConsumerState<_LiveMap> with VisibleInFront {
  final _map = MapController();
  final _ownLocation = OwnLocationTracker();
  final _reach = <String, LatLngBounds>{};
  LatLngBounds? _myReach;
  late LatLngBounds _region;
  LatLngBounds? _spread;
  late final LatLng _start;
  late LatLng _followed;
  late final StreamSubscription<LocationFailure> _ownFailures;
  var _ready = false;
  var _following = true;
  var _centerOnMe = false;

  @override
  void initState() {
    super.initState();
    _grow(widget.shares);
    _start = _followed = _targetOf(widget.shares)!;
    _ownLocation.addListener(_onOwnLocation);
    _ownFailures = _ownLocation.failures.listen(_explain);
  }

  @override
  void onVisibleInFrontChanged() =>
      _ownLocation.active = visibleInFront && widget.canShowMe;

  @override
  void didUpdateWidget(_LiveMap old) {
    super.didUpdateWidget(old);
    if (!widget.canShowMe) _ownLocation.hide();
    onVisibleInFrontChanged();
    _grow(widget.shares);
    final refocused = old.focusRequests != widget.focusRequests;
    if (refocused) _following = true;
    final target = _targetOf(widget.shares);
    if (!_following || target == null) return;
    if (!refocused && target == _followed) return;
    _followed = target;
    final zoom = refocused ? _focusZoom : null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _show(target, zoom));
  }

  @override
  void dispose() {
    unawaited(_ownFailures.cancel());
    _ownLocation.dispose();
    _map.dispose();
    super.dispose();
  }

  void _grow(List<LiveShareView> shares) {
    var grew = false;
    for (final share in shares) {
      final position = share.position;
      if (position == null) continue;
      final point = _pointOf(position.geo);
      final reach = _reach[share.userId];
      final grown = grownNeighbourhood(reach, point);
      if (identical(grown, reach)) continue;
      _reach[share.userId] = grown;
      _see(point);
      grew = true;
    }
    if (grew) _updateRegion();
  }

  void _updateRegion() => _region = regionOf([..._reach.values, ?_myReach]);

  void _see(LatLng point) {
    final seen = LatLngBounds(point, point);
    final spread = _spread;
    _spread = spread == null ? seen : regionOf([spread, seen]);
  }

  void _toggleOwnLocation() {
    _centerOnMe = !_ownLocation.showing;
    _ownLocation.toggle();
  }

  void _onOwnLocation() {
    final geo = _ownLocation.fix?.geo;
    if (geo != null) {
      final point = _pointOf(geo);
      final grown = grownNeighbourhood(_myReach, point);
      if (!identical(grown, _myReach)) {
        _myReach = grown;
        _see(point);
        _updateRegion();
      }
      if (_centerOnMe) {
        _centerOnMe = false;
        _following = false;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _show(point, _focusZoom),
        );
      }
    }
    setState(() {});
  }

  void _explain(LocationFailure reason) {
    final copy = locationFailureCopy(
      reason,
      goal: 'see where you are',
      servicesSettings: ref
          .read(platformCapabilitiesProvider)
          .locationServicesSettings,
    );
    final openSettings = copy.openSettings;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(copy.message),
        action: openSettings == null
            ? null
            : SnackBarAction(label: 'Open settings', onPressed: openSettings),
      ),
    );
  }

  LatLng? _targetOf(List<LiveShareView> shares) {
    final me = widget.room.client.userID;
    final placed = shares.where((share) => share.position != null);
    final target =
        placed.where((share) => share.userId == widget.focus).firstOrNull ??
        placed.where((share) => share.userId != me).firstOrNull ??
        placed.firstOrNull;
    return target == null ? null : _pointOf(target.position!.geo);
  }

  static LatLng _pointOf(GeoUri geo) => LatLng(geo.latitude, geo.longitude);

  void _show(LatLng point, double? zoom) {
    if (!mounted || !_ready) return;
    _map.move(point, math.max(_map.camera.zoom, zoom ?? _map.camera.zoom));
  }

  void _onMapReady() => _ready = true;

  void _onPositionChanged(MapCamera _, bool hasGesture) {
    if (hasGesture) _following = false;
  }

  @override
  Widget build(BuildContext context) {
    final tiles = ref.watch(mapTilesProvider).value;
    final colors = Theme.of(context).colorScheme;
    final placed = [
      for (final share in widget.shares)
        if (share.position case final position?)
          (share: share, geo: position.geo),
    ];
    final attribution = tiles?.attribution;
    final map = LayoutBuilder(
      builder: (context, constraints) => FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: _start,
          initialZoom: _focusZoom,
          minZoom: math.min(
            minFullMapZoom,
            zoomToFit(
              _spread!,
              constraints.biggest,
              padding: const EdgeInsets.all(_markerSize),
            ),
          ),
          maxZoom: maxTileZoom,
          cameraConstraint: CameraConstraint.containCenter(bounds: _region),
          backgroundColor: tiles == null
              ? Colors.transparent
              : colors.surfaceContainerHighest,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          onMapReady: _onMapReady,
          onPositionChanged: _onPositionChanged,
        ),
        children: [
          if (tiles != null)
            TileLayer(
              urlTemplate: tiles.urlTemplate,
              tileProvider: tiles.ephemeralTileProvider,
              userAgentPackageName: 'im.zuno.chat',
              maxNativeZoom: maxTileZoom.toInt(),
              panBuffer: 0,
            ),
          CircleLayer(
            circles: [
              for (final geo in [
                for (final entry in placed) entry.geo,
                ?_ownLocation.fix?.geo,
              ])
                if (geo.uncertaintyMeters case final meters?)
                  CircleMarker(
                    point: _pointOf(geo),
                    radius: meters,
                    useRadiusInMeter: true,
                    color: colors.primary.withValues(alpha: 0.12),
                    borderColor: colors.primary.withValues(alpha: 0.4),
                    borderStrokeWidth: 1,
                  ),
            ],
          ),
          MarkerLayer(
            markers: [
              for (final entry in placed)
                Marker(
                  point: _pointOf(entry.geo),
                  width: _markerSize,
                  height: _markerSize,
                  child: _PersonMarker(
                    room: widget.room,
                    userId: entry.share.userId,
                    fresh:
                        entry.share.statusAt(widget.now) !=
                        LiveShareStatus.notUpdating,
                    refreshing: entry.share.refreshingAt(widget.now),
                  ),
                ),
              if (_ownLocation.fix?.geo case final geo?)
                Marker(
                  point: _pointOf(geo),
                  width: _ownDotSize,
                  height: _ownDotSize,
                  child: const _OwnDot(),
                ),
            ],
          ),
          if (attribution != null) MapAttribution(attribution),
        ],
      ),
    );
    final layered = tiles != null
        ? map
        : Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: MapGridPainter(
                    background: colors.surfaceContainerHighest,
                    line: colors.outlineVariant,
                  ),
                ),
              ),
              Positioned.fill(child: map),
            ],
          );
    if (!widget.canShowMe) return layered;
    return Stack(
      children: [
        Positioned.fill(child: layered),
        Positioned(
          right: 12,
          bottom: 12,
          child: FloatingActionButton.small(
            heroTag: null,
            tooltip: _ownLocation.showing
                ? 'Hide your location'
                : 'Show your location',
            onPressed: _toggleOwnLocation,
            child: Icon(
              _ownLocation.showing
                  ? Icons.my_location
                  : Icons.location_searching,
            ),
          ),
        ),
      ],
    );
  }
}

class _OwnDot extends StatelessWidget {
  const _OwnDot();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.primary,
        border: Border.all(color: colors.surface, width: 3),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
      ),
    );
  }
}

class _WaitingForLocation extends StatelessWidget {
  const _WaitingForLocation();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: MapGridPainter(
        background: colors.surfaceContainerHighest,
        line: colors.outlineVariant,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.share_location_outlined,
              size: 32,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              'Waiting for location',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonMarker extends StatelessWidget {
  final Room room;
  final String userId;
  final bool fresh;
  final bool refreshing;

  const _PersonMarker({
    required this.room,
    required this.userId,
    required this.fresh,
    required this.refreshing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final user = room.unsafeGetUserFromMemoryOrFallback(userId);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.surface,
            border: Border.all(
              color: fresh && !refreshing
                  ? colors.primary
                  : colors.outlineVariant,
              width: 3,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: MxcAvatar(
              client: room.client,
              avatarUrl: user.avatarUrl,
              fallbackText: user.calcDisplayname(),
              toneSeed: userId,
              radius: _markerSize / 2 - 5,
            ),
          ),
        ),
        if (refreshing) const CircularProgressIndicator(strokeWidth: 3),
      ],
    );
  }
}

class _Sharers extends ConsumerWidget {
  final Room room;
  final List<LiveShareView> shares;
  final DateTime now;
  final ValueChanged<String> onFocus;

  const _Sharers({
    required this.room,
    required this.shares,
    required this.now,
    required this.onFocus,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = room.client.userID;
    final clock = liveClockFormat(context);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.4,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final share in shares)
              _SharerRow(
                room: room,
                share: share,
                mine: share.userId == me,
                status: liveShareStatusText(share, now, clock),
                onFocus: onFocus,
                onStop: () =>
                    ref.read(liveLocationSharingProvider).stopIn(room.id),
                onOpenInMaps: (geo) => openInMaps(
                  context,
                  geo,
                  ref.read(platformCapabilitiesProvider).mapsApp,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SharerRow extends StatelessWidget {
  final Room room;
  final LiveShareView share;
  final bool mine;
  final String status;
  final ValueChanged<String> onFocus;
  final VoidCallback onStop;
  final ValueChanged<GeoUri> onOpenInMaps;

  const _SharerRow({
    required this.room,
    required this.share,
    required this.mine,
    required this.status,
    required this.onFocus,
    required this.onStop,
    required this.onOpenInMaps,
  });

  @override
  Widget build(BuildContext context) {
    final user = room.unsafeGetUserFromMemoryOrFallback(share.userId);
    final name = user.calcDisplayname();
    final position = share.position;
    final Widget? trailing;
    if (mine) {
      trailing = TextButton(
        onPressed: onStop,
        child: const Text('Stop sharing'),
      );
    } else if (position != null) {
      trailing = IconButton(
        tooltip: 'Open in maps app',
        icon: const Icon(Icons.map_outlined),
        onPressed: () => onOpenInMaps(position.geo),
      );
    } else {
      trailing = null;
    }
    return ListTile(
      leading: MxcAvatar(
        client: room.client,
        avatarUrl: user.avatarUrl,
        fallbackText: name,
        toneSeed: share.userId,
      ),
      title: Text(mine ? 'You' : name),
      subtitle: Text(status),
      onTap: position == null ? null : () => onFocus(share.userId),
      trailing: trailing,
    );
  }
}
