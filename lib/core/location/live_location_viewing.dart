import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../errors/best_effort.dart';
import '../matrix/connectivity_provider.dart';
import '../matrix/ephemeral_to_device.dart';
import '../matrix/matrix_client_provider.dart';
import '../matrix/olm_sender.dart';
import 'live_location_policy.dart';
import 'live_location_protocol.dart';
import 'live_location_sharing.dart';

const _heldFor = Duration(seconds: 60);
const _maxHeld = 64;
const _maxFutureSkew = Duration(minutes: 5);
const _keyQueryGap = Duration(minutes: 1);
const _freshFor = Duration(seconds: 60);
const _refreshFor = Duration(minutes: 2);

enum LiveShareStatus { waiting, live, notUpdating }

@immutable
class LiveShareView {
  final String userId;
  final String shareId;
  final String deviceId;
  final DateTime endsAt;
  final LivePosition? position;
  final bool fromThisDevice;
  final DateTime? refreshingSince;

  const LiveShareView({
    required this.userId,
    required this.shareId,
    required this.deviceId,
    required this.endsAt,
    required this.position,
    required this.fromThisDevice,
    this.refreshingSince,
  });

  bool refreshingAt(DateTime now) {
    final since = refreshingSince;
    final position = this.position;
    return since != null &&
        position != null &&
        now.difference(position.at) > _freshFor &&
        now.difference(since) < _refreshFor;
  }

  LiveShareStatus statusAt(DateTime now) {
    final position = this.position;
    if (position == null) return LiveShareStatus.waiting;
    return now.difference(position.at) > liveStaleAfter
        ? LiveShareStatus.notUpdating
        : LiveShareStatus.live;
  }

  LiveShareView withPosition(LivePosition? position) => LiveShareView(
    userId: userId,
    shareId: shareId,
    deviceId: deviceId,
    endsAt: endsAt,
    position: position,
    fromThisDevice: fromThisDevice,
    refreshingSince: refreshingSince,
  );

  @override
  bool operator ==(Object other) =>
      other is LiveShareView &&
      other.userId == userId &&
      other.shareId == shareId &&
      other.deviceId == deviceId &&
      other.endsAt == endsAt &&
      other.position == position &&
      other.fromThisDevice == fromThisDevice &&
      other.refreshingSince == refreshingSince;

  @override
  int get hashCode => Object.hash(
    userId,
    shareId,
    deviceId,
    endsAt,
    position,
    fromThisDevice,
    refreshingSince,
  );
}

LiveShareView? liveShareStartedBy(List<LiveShareView> shares, Event message) {
  final start = liveLocationStartOf(message);
  if (start == null) return null;
  return shares
      .where(
        (share) =>
            share.userId == message.senderId && share.shareId == start.shareId,
      )
      .firstOrNull;
}

class LiveLocationWatch {
  LiveLocationWatch._(this._release);

  final void Function() _release;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    _release();
  }
}

typedef _Held = ({String shareId, String deviceId, LivePosition position});

typedef _Candidate = ({
  String roomId,
  String userId,
  String deviceId,
  String shareId,
  LivePosition position,
  DateTime heldAt,
});

typedef _WatchTarget = ({
  String roomId,
  String userId,
  String deviceId,
  String shareId,
});

String _targetKey(_WatchTarget target) =>
    '${target.roomId}|${target.userId}|${target.deviceId}|${target.shareId}';

class LiveLocationViewing {
  LiveLocationViewing({
    required Client client,
    required this._isOffline,
    this._now = DateTime.now,
  }) : _client = client {
    _subscriptions.addAll([
      client.onToDeviceEvent.stream.listen(_onToDevice),
      client.onSync.stream.listen(_onSync),
      client.onSyncStatus.stream.listen(_onSyncStatus),
    ]);
  }

  final Client _client;
  final bool Function() _isOffline;
  final DateTime Function() _now;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _positions = <String, Map<String, _Held>>{};
  final _held = <String, _Candidate>{};
  final _changes = StreamController<String>.broadcast();
  final _watchedRooms = <String, int>{};
  final _signaled = <String, _WatchTarget>{};
  final _keysQueriedAt = <String, DateTime>{};
  final _membersRequested = <String>{};
  final _ends = <String, DateTime>{};
  final _pending = <String, DateTime>{};
  Timer? _renewal;
  Timer? _deadline;
  bool _deviceListsChanged = false;
  bool _disposed = false;

  Stream<String> get changedRooms => _changes.stream;

  List<LiveShareView> sharesIn(Room room) {
    if (!room.encrypted) return const [];
    final now = _now();
    final ignored = _client.ignoredUsers.toSet();
    final views = <LiveShareView>[];
    DateTime? earliest;
    for (final userId in [...?room.states[liveLocationStateType]?.keys]) {
      final state = _liveState(room, userId, now, ignored);
      if (state == null) continue;
      final held = _positions[room.id]?[userId];
      final matches =
          held != null &&
          held.shareId == state.shareId &&
          held.deviceId == state.deviceId;
      views.add(
        LiveShareView(
          userId: userId,
          shareId: state.shareId,
          deviceId: state.deviceId,
          endsAt: state.endsAt,
          position: matches ? held.position : null,
          fromThisDevice:
              userId == _client.userID && state.deviceId == _client.deviceID,
          refreshingSince:
              _pending[_targetKey((
                roomId: room.id,
                userId: userId,
                deviceId: state.deviceId,
                shareId: state.shareId,
              ))],
        ),
      );
      if (earliest == null || state.endsAt.isBefore(earliest)) {
        earliest = state.endsAt;
      }
    }
    _noteEnd(room.id, earliest);
    views.sort((a, b) => a.userId.compareTo(b.userId));
    return views;
  }

  LiveLocationWatch watch(String roomId) {
    _watchedRooms.update(roomId, (count) => count + 1, ifAbsent: () => 1);
    _refreshWatches();
    return LiveLocationWatch._(() {
      final count = (_watchedRooms[roomId] ?? 1) - 1;
      if (count <= 0) {
        _watchedRooms.remove(roomId);
      } else {
        _watchedRooms[roomId] = count;
      }
      _refreshWatches();
    });
  }

  void onConnectivityRestored() => _refreshWatches();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _renewal?.cancel();
    _deadline?.cancel();
    _positions.clear();
    _held.clear();
    unawaited(_changes.close());
  }

  LiveShareState? _liveState(
    Room room,
    String userId,
    DateTime now,
    Set<String> ignored,
  ) {
    if (ignored.contains(userId)) return null;
    final state = liveShareStateOf(room, userId);
    if (state == null || !state.isOpenAt(now)) return null;
    if (!_isJoined(room, userId)) return null;
    if (_deviceGone(userId, state.deviceId)) return null;
    return state;
  }

  bool _isJoined(Room room, String userId) {
    final member = room.getState(EventTypes.RoomMember, userId);
    if (member != null) {
      return member.content['membership'] == Membership.join.name;
    }
    final key = '${room.id}|$userId';
    if (_membersRequested.add(key)) unawaited(_loadMember(room, userId));
    return false;
  }

  Future<void> _loadMember(Room room, String userId) async {
    try {
      await room.requestUser(userId, ignoreErrors: true);
    } catch (error) {
      logCaught('live location member', error);
    }
    if (!_disposed && room.getState(EventTypes.RoomMember, userId) != null) {
      _changes.add(room.id);
    }
  }

  bool _deviceGone(String userId, String deviceId) {
    final devices = _client.userDeviceKeys[userId];
    if (devices == null || devices.outdated) return false;
    return !devices.deviceKeys.containsKey(deviceId);
  }

  void _noteEnd(String roomId, DateTime? earliest) {
    final previous = _ends[roomId];
    if (earliest == null) {
      _ends.remove(roomId);
    } else {
      _ends[roomId] = earliest;
    }
    if (previous != earliest) _armDeadline();
  }

  void _armDeadline() {
    _deadline?.cancel();
    _deadline = null;
    if (_disposed) return;
    final now = _now();
    DateTime? next;
    for (final end in _ends.values) {
      if (next == null || end.isBefore(next)) next = end;
    }
    for (final candidate in _held.values) {
      final expiry = candidate.heldAt.add(_heldFor);
      if (next == null || expiry.isBefore(next)) next = expiry;
    }
    if (next == null) return;
    final wait = next.difference(now);
    _deadline = Timer(wait.isNegative ? Duration.zero : wait, _onDeadline);
  }

  void _onDeadline() {
    final now = _now();
    _expireHeld(now);
    _prune(now);
    for (final MapEntry(key: roomId, value: end) in [..._ends.entries]) {
      if (now.isBefore(end)) continue;
      _ends.remove(roomId);
      _changes.add(roomId);
    }
    _refreshWatches();
    _armDeadline();
  }

  void _onToDevice(ToDeviceEvent event) {
    if (event.type != liveLocationPositionType) return;
    final device = olmSenderDevice(_client, event);
    if (device == null) return;
    final message = parseLivePosition(event.content);
    if (message == null) return;
    final now = _now();
    if (message.position.at.isAfter(now.add(_maxFutureSkew))) return;
    if (_client.ignoredUsers.contains(device.userId)) return;
    final candidate = (
      roomId: message.roomId,
      userId: device.userId,
      deviceId: device.deviceId!,
      shareId: message.shareId,
      position: message.position,
      heldAt: now,
    );
    if (!_take(candidate)) _hold(candidate);
  }

  bool _take(_Candidate candidate) {
    final room = _client.getRoomById(candidate.roomId);
    if (room == null || room.membership != Membership.join) return false;
    if (!room.encrypted) return false;
    final state = _liveState(
      room,
      candidate.userId,
      _now(),
      _client.ignoredUsers.toSet(),
    );
    if (state == null ||
        state.shareId != candidate.shareId ||
        state.deviceId != candidate.deviceId) {
      return false;
    }
    final byUser = _positions.putIfAbsent(room.id, () => {});
    final held = byUser[candidate.userId];
    if (held != null &&
        held.shareId == candidate.shareId &&
        held.position.at.isAfter(candidate.position.at)) {
      return true;
    }
    byUser[candidate.userId] = (
      shareId: candidate.shareId,
      deviceId: candidate.deviceId,
      position: candidate.position,
    );
    if (_now().difference(candidate.position.at) <= _freshFor) {
      _pending.remove(
        _targetKey((
          roomId: room.id,
          userId: candidate.userId,
          deviceId: candidate.deviceId,
          shareId: candidate.shareId,
        )),
      );
    }
    _noteEnd(room.id, _earlier(_ends[room.id], state.endsAt));
    _changes.add(room.id);
    return true;
  }

  DateTime _earlier(DateTime? a, DateTime b) =>
      a == null || b.isBefore(a) ? b : a;

  void _hold(_Candidate candidate) {
    final room = _client.getRoomById(candidate.roomId);
    if (room == null || room.membership != Membership.join) return;
    final key = '${candidate.roomId}|${candidate.userId}';
    final existing = _held[key];
    if (existing != null &&
        existing.position.at.isAfter(candidate.position.at)) {
      return;
    }
    _held[key] = candidate;
    if (_held.length > _maxHeld) {
      final oldest = _held.entries.reduce(
        (a, b) => a.value.heldAt.isAfter(b.value.heldAt) ? b : a,
      );
      _held.remove(oldest.key);
    }
    _armDeadline();
  }

  void _expireHeld(DateTime now) {
    _held.removeWhere(
      (_, candidate) => now.difference(candidate.heldAt).abs() >= _heldFor,
    );
  }

  void _onSync(SyncUpdate update) {
    final now = _now();
    _expireHeld(now);
    _held.removeWhere((_, candidate) => _take(candidate));
    _prune(now);
    if (update.deviceLists?.changed?.isNotEmpty ?? false) {
      _deviceListsChanged = true;
    }
    final ignoredChanged =
        update.accountData?.any(
          (event) => event.type == 'm.ignored_user_list',
        ) ??
        false;
    final touched = <String>{
      for (final MapEntry(key: roomId, value: joined)
          in (update.rooms?.join ?? const <String, JoinedRoomUpdate>{}).entries)
        if ([...?joined.state, ...?joined.timeline?.events].any(
          (event) =>
              event.type == liveLocationStateType ||
              event.type == EventTypes.RoomMember,
        ))
          roomId,
      ...?update.rooms?.leave?.keys,
      if (ignoredChanged) ...[..._ends.keys, ..._watchedRooms.keys],
    };
    touched.forEach(_changes.add);
    _refreshWatches();
    _armDeadline();
  }

  void _onSyncStatus(SyncStatusUpdate status) {
    if (status.status != SyncStatus.finished || !_deviceListsChanged) return;
    _deviceListsChanged = false;
    _prune(_now());
    for (final roomId in {..._ends.keys, ..._watchedRooms.keys}) {
      _changes.add(roomId);
    }
    _refreshWatches();
  }

  void _prune(DateTime now) {
    final ignored = _client.ignoredUsers.toSet();
    for (final roomId in [..._positions.keys]) {
      final byUser = _positions[roomId]!;
      final room = _client.getRoomById(roomId);
      final before = byUser.length;
      byUser.removeWhere((userId, held) {
        if (room == null || room.membership != Membership.join) return true;
        final state = _liveState(room, userId, now, ignored);
        return state == null ||
            state.shareId != held.shareId ||
            state.deviceId != held.deviceId;
      });
      if (byUser.isEmpty) _positions.remove(roomId);
      if (byUser.length != before) _changes.add(roomId);
    }
  }

  void _refreshWatches({bool renew = false}) {
    if (_disposed) return;
    final desired = <String, _WatchTarget>{};
    for (final roomId in _watchedRooms.keys) {
      final room = _client.getRoomById(roomId);
      if (room == null) continue;
      for (final view in sharesIn(room)) {
        if (view.fromThisDevice) continue;
        final target = (
          roomId: roomId,
          userId: view.userId,
          deviceId: view.deviceId,
          shareId: view.shareId,
        );
        desired[_targetKey(target)] = target;
      }
    }
    final offline = _isOffline();
    for (final MapEntry(:key, value: target) in [..._signaled.entries]) {
      if (desired.containsKey(key)) continue;
      _signaled.remove(key);
      if (_pending.remove(key) != null) _changes.add(target.roomId);
      if (!offline) unawaited(_sendWatch(target, active: false));
    }
    if (!offline) {
      for (final MapEntry(:key, value: target) in desired.entries) {
        final first = !_signaled.containsKey(key);
        if (!first && !renew) continue;
        _signaled[key] = target;
        if (first) {
          _pending[key] = _now();
          _changes.add(target.roomId);
        }
        unawaited(_signal(key, target));
      }
    }
    if (desired.isEmpty) {
      _renewal?.cancel();
      _renewal = null;
    } else {
      _renewal ??= Timer.periodic(
        liveWatchRenewInterval,
        (_) => _refreshWatches(renew: true),
      );
    }
  }

  Future<void> _signal(String key, _WatchTarget target) async {
    if (await _sendWatch(target, active: true)) return;
    if (!identical(_signaled[key], target)) return;
    _signaled.remove(key);
    if (_pending.remove(key) != null) _changes.add(target.roomId);
  }

  Future<bool> _sendWatch(_WatchTarget target, {required bool active}) async {
    try {
      final device = await _deviceOf(target.userId, target.deviceId);
      if (device == null) return false;
      await sendEphemeralToDevice(
        _client,
        [device],
        liveLocationWatchType,
        liveWatchContent(
          roomId: target.roomId,
          shareId: target.shareId,
          active: active,
        ),
      );
      return true;
    } catch (error) {
      logCaught('live location watch', error.runtimeType);
      return false;
    }
  }

  Future<DeviceKeys?> _deviceOf(String userId, String deviceId) async {
    final known = _client.userDeviceKeys[userId]?.deviceKeys[deviceId];
    if (known != null) return known;
    final now = _now();
    final lastQuery = _keysQueriedAt[userId];
    if (lastQuery != null &&
        !now.isBefore(lastQuery) &&
        now.difference(lastQuery) < _keyQueryGap) {
      return null;
    }
    _keysQueriedAt[userId] = now;
    await _client.updateUserDeviceKeys(additionalUsers: {userId});
    return _client.userDeviceKeys[userId]?.deviceKeys[deviceId];
  }
}

final liveLocationViewingProvider = Provider<LiveLocationViewing>((ref) {
  final client = ref.watch(matrixClientProvider);
  ref.watch(isLoggedInProvider);
  final viewing = LiveLocationViewing(
    client: client,
    isOffline: () => ref.read(isOfflineProvider).value ?? false,
  );
  ref.listen(isOfflineProvider, (previous, next) {
    if (becameOnline(previous, next)) viewing.onConnectivityRestored();
  });
  ref.onDispose(viewing.dispose);
  return viewing;
});

final liveSharesProvider = Provider.autoDispose
    .family<List<LiveShareView>, String>((ref, roomId) {
      final client = ref.watch(matrixClientProvider);
      final viewing = ref.watch(liveLocationViewingProvider);
      final sharing = ref.watch(liveLocationSharingProvider);
      final changes = viewing.changedRooms
          .where((changed) => changed == roomId)
          .listen((_) => ref.invalidateSelf());
      void onOwnShares() => ref.invalidateSelf();
      void onOwnPosition() {
        if (sharing.isSharingIn(roomId)) ref.invalidateSelf();
      }

      sharing.shares.addListener(onOwnShares);
      sharing.position.addListener(onOwnPosition);
      ref.onDispose(() {
        unawaited(changes.cancel());
        sharing.shares.removeListener(onOwnShares);
        sharing.position.removeListener(onOwnPosition);
      });
      final room = client.getRoomById(roomId);
      if (room == null) return const [];
      final ownPosition = sharing.position.value;
      return [
        for (final view in viewing.sharesIn(room))
          if (!view.fromThisDevice)
            view
          else if (sharing.isSharingIn(roomId))
            view.withPosition(ownPosition),
      ];
    });
