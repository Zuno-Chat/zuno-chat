import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../errors/best_effort.dart';
import '../errors/retry_backoff.dart';
import '../matrix/connectivity_provider.dart';
import '../matrix/ephemeral_to_device.dart';
import '../matrix/matrix_client_provider.dart';
import '../matrix/olm_sender.dart';
import 'live_location_availability.dart';
import 'live_location_capture.dart';
import 'live_location_notice.dart';
import 'live_location_policy.dart';
import 'live_location_protocol.dart';
import 'live_location_recipients.dart';
import 'live_share_sweep.dart';

const _clearBound = Duration(seconds: 5);
const _sendDeadline = Duration(seconds: 20);
const _coarseAfterUnwatched = Duration(seconds: 30);
const _firstSendGap = Duration(seconds: 5);
const _ignoredUserList = 'm.ignored_user_list';

@immutable
class OwnLiveShare {
  final String roomId;
  final String shareId;
  final DateTime endsAt;

  const OwnLiveShare({
    required this.roomId,
    required this.shareId,
    required this.endsAt,
  });

  @override
  bool operator ==(Object other) =>
      other is OwnLiveShare &&
      other.roomId == roomId &&
      other.shareId == shareId &&
      other.endsAt == endsAt;

  @override
  int get hashCode => Object.hash(roomId, shareId, endsAt);
}

enum LiveShareStartFailure {
  notAllowed,
  alreadySharing,
  captureUnavailable,
  failed,
}

class LiveShareStartException implements Exception {
  final LiveShareStartFailure reason;

  const LiveShareStartException(this.reason);
}

class _Watcher {
  final DeviceKeys device;
  final DateTime expiresAt;

  const _Watcher(this.device, this.expiresAt);
}

class _ActiveShare {
  _ActiveShare({
    required this.roomId,
    required this.shareId,
    required this.endsAt,
  });

  final String roomId;
  final String shareId;
  final DateTime endsAt;
  final watchers = <String, _Watcher>{};
  final firstSends = <String>{};
  final watcherSentAt = <String, DateTime>{};
  final startEventIds = <String>{};
  bool published = false;
  String? stateEventId;
  Timer? endTimer;
  LiveSendRecord? lastToEveryone;
  LiveSendRecord? lastToWatchers;
  bool everyoneUndelivered = false;
  List<DeviceKeys> recipients = const [];
  bool recipientsStale = true;
  bool sending = false;
  bool resend = false;
  bool verifying = false;
  bool reverify = false;

  OwnLiveShare get view =>
      OwnLiveShare(roomId: roomId, shareId: shareId, endsAt: endsAt);
}

String _deviceKey(DeviceKeys device) => '${device.userId}|${device.deviceId}';

class LiveLocationSharing {
  LiveLocationSharing({
    required Client client,
    required LiveLocationCapture capture,
    required this._isOffline,
    this._recipients = liveLocationRecipients,
    this._now = DateTime.now,
  }) : _client = client,
       _capture = capture {
    _subscriptions.addAll([
      capture.events.listen(_onCaptureEvent),
      capture.stopRequests.listen((_) => unawaited(stopAll())),
      client.onToDeviceEvent.stream.listen(_onToDevice),
      client.onTimelineEvent.stream.listen(_onTimelineEvent),
      client.onSync.stream.listen(_onSync),
    ]);
    _sweep.sweep();
  }

  final Client _client;
  final LiveLocationCapture _capture;
  final bool Function() _isOffline;
  final Future<List<DeviceKeys>> Function(Room room) _recipients;
  final DateTime Function() _now;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _active = <String, _ActiveShare>{};
  final _stateWrites = <String, Future<void>>{};
  late final _sweep = LiveShareSweep(
    client: _client,
    isActive: _active.containsKey,
    writeState: _writeState,
    echoState: _echoState,
    now: _now,
  );
  late final _unreachable = UnreachableDevices(_client);
  final _shares = ValueNotifier<List<OwnLiveShare>>(const []);
  final _needsSync = ValueNotifier<bool>(false);
  final _position = ValueNotifier<LivePosition?>(null);
  final _captureLost = StreamController<LiveCaptureFailure>.broadcast();
  LiveLocationMode? _mode;
  LivePosition? _latest;
  int _latestSeq = -1;
  DateTime? _unwatchedSince;
  int _inFlight = 0;
  int _clearing = 0;
  Completer<void>? _idle;
  bool _disposed = false;

  ValueListenable<List<OwnLiveShare>> get shares => _shares;

  ValueListenable<bool> get needsSync => _needsSync;

  ValueListenable<LivePosition?> get position => _position;

  Stream<LiveCaptureFailure> get captureLost => _captureLost.stream;

  bool isSharingIn(String roomId) => _active.containsKey(roomId);

  Future<void> start(
    Room room,
    LiveLocationDuration duration,
    LivePosition firstFix,
  ) async {
    if (_active.containsKey(room.id)) {
      throw const LiveShareStartException(LiveShareStartFailure.alreadySharing);
    }
    if (liveLocationAvailability(room, sharingHere: false) !=
        LiveLocationAvailability.available) {
      throw const LiveShareStartException(LiveShareStartFailure.notAllowed);
    }
    final userId = _client.userID;
    final deviceId = _client.deviceID;
    if (userId == null || deviceId == null) {
      throw const LiveShareStartException(LiveShareStartFailure.failed);
    }
    final startedAt = _now();
    final share = _ActiveShare(
      roomId: room.id,
      shareId: newLiveShareId(),
      endsAt: startedAt.add(duration.duration),
    );
    _active[room.id] = share;
    _publish();
    try {
      await _startCaptureIfIdle();
    } on LiveCaptureUnavailable {
      _active.remove(room.id);
      _publish();
      throw const LiveShareStartException(
        LiveShareStartFailure.captureUnavailable,
      );
    }
    final state = LiveShareState(
      shareId: share.shareId,
      deviceId: deviceId,
      endsAt: share.endsAt,
    ).toContent();
    try {
      share.stateEventId = await _writeState(room.id, state);
    } catch (error) {
      logCaught('live location share', error);
      if (_active[room.id] == share) _active.remove(room.id);
      _publish();
      await _settleCapture();
      throw LiveShareStartException(
        error is MatrixException && error.error == MatrixError.M_FORBIDDEN
            ? LiveShareStartFailure.notAllowed
            : LiveShareStartFailure.failed,
      );
    }
    if (_active[room.id] != share) return;
    share.published = true;
    _echoState(room, share.stateEventId!, state);
    share.endTimer = Timer(share.endsAt.difference(startedAt), _endDue);
    if (_latest == null) _setLatest(firstFix, -1);
    _publish();
    await _settleCapture();
    unawaited(_sendStartMessage(room, share, duration));
    if (share.reverify) {
      share.reverify = false;
      unawaited(_verifyStillOurs(share));
    }
    unawaited(_evaluate(share));
  }

  Future<void> stop(String roomId) async {
    final share = _active.remove(roomId);
    if (share == null) return;
    share.endTimer?.cancel();
    _publish();
    _clearing++;
    _inFlight++;
    try {
      await _clearState(roomId).timeout(_clearBound);
    } on TimeoutException {
      logCaught('live location stop', 'clear still pending');
    } finally {
      _clearing--;
      _settle();
    }
    await _settleCapture();
  }

  Future<void> stopIn(String roomId) async {
    if (_active.containsKey(roomId)) return stop(roomId);
    await _clearState(roomId);
  }

  Future<void> stopShareStartedBy(Event event) async {
    final me = _client.userID;
    final start = liveLocationStartOf(event);
    if (me == null || start == null || event.senderId != me) return;
    final room = event.room;
    final shareId =
        _active[room.id]?.shareId ?? liveShareStateOf(room, me)?.shareId;
    if (shareId != start.shareId) return;
    await stopIn(room.id);
  }

  Future<void> stopAll({Duration? within}) async {
    final stopping = Future.wait([
      for (final roomId in [..._active.keys]) stop(roomId),
    ]);
    if (within == null) {
      await stopping;
      return;
    }
    await stopping.timeout(within, onTimeout: () => const []);
  }

  void onConnectivityRestored() {
    _endDue();
    for (final share in [..._active.values]) {
      unawaited(_evaluate(share, resendUndelivered: true));
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    for (final share in _active.values) {
      share.endTimer?.cancel();
    }
    _active.clear();
    if (_mode != null) {
      _mode = null;
      unawaited(_capture.stop());
    }
    _shares.dispose();
    _needsSync.dispose();
    _position.dispose();
    unawaited(_captureLost.close());
  }

  void _publish() {
    if (_disposed) return;
    _shares.value = [
      for (final share in _active.values)
        if (share.published) share.view,
    ];
    _needsSync.value = _active.isNotEmpty;
  }

  Future<void> _startCaptureIfIdle() async {
    if (_mode != null) return;
    final notice = _notice();
    if (notice == null) return;
    _mode = LiveLocationMode.coarse;
    try {
      await _capture.start(LiveLocationMode.coarse, notice);
    } catch (_) {
      _mode = null;
      rethrow;
    }
  }

  Future<void> _settleCapture() async {
    if (_disposed) return;
    if (_active.isEmpty) {
      if (_clearing == 0) await _stopCapture();
      return;
    }
    final notice = _notice();
    if (_mode != null && notice != null) await _capture.updateNotice(notice);
  }

  Future<void> _stopCapture() async {
    if (_mode == null) return;
    _mode = null;
    _latest = null;
    _latestSeq = -1;
    _unwatchedSince = null;
    if (!_disposed) _position.value = null;
    await _capture.stop();
  }

  LiveLocationNotice? _notice() {
    final entries = [
      for (final share in _active.values)
        if (_client.getRoomById(share.roomId) case final room?)
          (room: room, endsAt: share.endsAt),
    ];
    return entries.isEmpty ? null : liveLocationNotice(entries);
  }

  void _setLatest(LivePosition position, int seq) {
    _latest = position;
    _latestSeq = seq;
    if (!_disposed) _position.value = position;
  }

  void _endDue() {
    final now = _now();
    for (final share in [..._active.values]) {
      if (!share.endsAt.isAfter(now)) unawaited(stop(share.roomId));
    }
  }

  Future<String> _writeState(String roomId, Map<String, Object?> content) {
    final userId = _client.userID;
    if (userId == null) return Future.error(StateError('signed out'));
    final previous = _stateWrites[roomId] ?? Future<void>.value();
    final write = previous.then(
      (_) => retryWithBackoff(
        () => _client.setRoomStateWithKey(
          roomId,
          liveLocationStateType,
          userId,
          content,
        ),
        label: 'live location state',
        retryIf: (error) => error is! MatrixException,
      ),
    );
    _stateWrites[roomId] = write.then<void>((_) {}, onError: (_) {});
    return write;
  }

  void _echoState(Room room, String eventId, Map<String, Object?> content) {
    final userId = _client.userID;
    if (userId == null) return;
    room.setState(
      Event(
        type: liveLocationStateType,
        stateKey: userId,
        senderId: userId,
        eventId: eventId,
        originServerTs: _now(),
        content: content,
        room: room,
      ),
    );
  }

  Future<void> _clearState(String roomId) async {
    try {
      final eventId = await _writeState(roomId, const {});
      final room = _client.getRoomById(roomId);
      if (room != null && !_active.containsKey(roomId)) {
        _echoState(room, eventId, const {});
      }
    } catch (error) {
      logCaught('live location stop', error);
    }
  }

  Future<void> _sendStartMessage(
    Room room,
    _ActiveShare share,
    LiveLocationDuration duration,
  ) async {
    try {
      final eventId = await room.sendEvent(
        liveLocationStartContent(
          shareId: share.shareId,
          endsAt: share.endsAt,
          duration: duration,
        ),
      );
      if (eventId != null) share.startEventIds.add(eventId);
    } catch (error) {
      logCaught('live location start message', error);
    }
  }

  void _onCaptureEvent(LiveCaptureEvent event) {
    switch (event) {
      case LiveCaptureFix(:final fix):
        unawaited(_onFix(fix));
      case LiveCaptureLost(:final reason):
        if (_active.isEmpty) return;
        if (reason != LiveCaptureFailure.ended) _captureLost.add(reason);
        unawaited(stopAll());
    }
  }

  Future<void> _onFix(LiveFix fix) async {
    _endDue();
    if (_mode != null && _isNewer(fix)) {
      _setLatest(fix.position, fix.seq);
      _refreshMode();
      for (final share in [..._active.values]) {
        unawaited(_evaluate(share));
      }
    }
    await _whenIdle();
    await _capture.releaseWakeLock(fix.seq);
  }

  bool _isNewer(LiveFix fix) {
    final latest = _latest;
    if (latest == null) return true;
    if (_latestSeq < 0) return !fix.position.at.isBefore(latest.at);
    return fix.seq > _latestSeq;
  }

  void _refreshMode() {
    final current = _mode;
    if (current == null) return;
    final now = _now();
    var watched = false;
    for (final share in _active.values) {
      share.watchers.removeWhere((_, watcher) => _expired(watcher, now));
      if (share.watchers.isNotEmpty) watched = true;
    }
    if (watched) {
      _unwatchedSince = null;
    } else {
      final since = _unwatchedSince ??= now;
      final settled =
          now.isBefore(since) || now.difference(since) >= _coarseAfterUnwatched;
      if (!settled) return;
    }
    final mode = liveCaptureModeFor(watched: watched);
    if (mode == current) return;
    _mode = mode;
    unawaited(_capture.setMode(mode));
  }

  bool _expired(_Watcher watcher, DateTime now) =>
      !now.isBefore(watcher.expiresAt) ||
      watcher.expiresAt.difference(now) > liveWatchLifetime;

  void _pruneWatchers(_ActiveShare share, Room room, Set<String> ignored) {
    final now = _now();
    share.watchers.removeWhere(
      (_, watcher) =>
          _expired(watcher, now) ||
          !isLiveLocationPeer(room, watcher.device, ignored: ignored),
    );
    share.firstSends.removeWhere((key) => !share.watchers.containsKey(key));
    share.watcherSentAt.removeWhere(
      (_, sentAt) => now.difference(sentAt).abs() > liveWatchLifetime,
    );
  }

  Future<void> _evaluate(
    _ActiveShare share, {
    bool resendUndelivered = false,
  }) async {
    if (_active[share.roomId] != share || !share.published) return;
    if (share.sending) {
      share.resend = true;
      return;
    }
    final latest = _latest;
    if (latest == null || _isOffline()) return;
    final now = _now();
    if (!share.endsAt.isAfter(now)) return _endDue();
    final room = _client.getRoomById(share.roomId);
    if (room == null) return;
    final ignored = _client.ignoredUsers.toSet();
    _pruneWatchers(share, room, ignored);
    final audience = resendUndelivered && share.everyoneUndelivered
        ? LiveAudience.everyone
        : nextLiveAudience(
            latest: latest,
            lastToEveryone: share.lastToEveryone,
            lastToWatchers: share.lastToWatchers,
            hasWatchers: share.watchers.isNotEmpty,
            now: now,
          );
    final firsts = [
      for (final key in share.firstSends)
        if (share.watchers[key] case final watcher?)
          if (_firstSendDue(share, key, now)) watcher.device,
    ];
    if (audience == null && firsts.isEmpty) return;
    share.sending = true;
    _inFlight++;
    try {
      final candidates = switch (audience) {
        LiveAudience.everyone => await _currentRecipients(share, room),
        LiveAudience.watchers => [
          for (final watcher in share.watchers.values) watcher.device,
        ],
        null => firsts,
      };
      if (_active[share.roomId] != share) return;
      final targets = [
        for (final device in candidates)
          if (isLiveLocationPeer(room, device, ignored: ignored) &&
              !_unreachable.contains(device, now))
            device,
      ];
      final delivered = targets.isEmpty || await _send(share, targets, latest);
      final record = LiveSendRecord(position: latest, sentAt: now);
      switch (audience) {
        case LiveAudience.everyone:
          share.lastToEveryone = record;
          share.everyoneUndelivered = !delivered;
          if (delivered) _unreachable.noteWithoutSession(targets, now);
        case LiveAudience.watchers:
          share.lastToWatchers = record;
        case null:
          break;
      }
      if (delivered) {
        for (final device in targets) {
          final key = _deviceKey(device);
          if (!share.watchers.containsKey(key)) continue;
          share.watcherSentAt[key] = now;
          share.firstSends.remove(key);
        }
      }
    } catch (error) {
      logCaught('live location send', error.runtimeType);
    } finally {
      share.sending = false;
      if (share.resend) {
        share.resend = false;
        unawaited(_evaluate(share));
      }
      _settle();
    }
  }

  bool _firstSendDue(_ActiveShare share, String key, DateTime now) {
    final last = share.watcherSentAt[key];
    return last == null ||
        now.isBefore(last) ||
        now.difference(last) >= _firstSendGap;
  }

  Future<List<DeviceKeys>> _currentRecipients(
    _ActiveShare share,
    Room room,
  ) async {
    if (!share.recipientsStale) return share.recipients;
    share.recipientsStale = false;
    try {
      share.recipients = await _recipients(room);
    } catch (error) {
      share.recipientsStale = true;
      rethrow;
    }
    return share.recipients;
  }

  Future<bool> _send(
    _ActiveShare share,
    List<DeviceKeys> devices,
    LivePosition position,
  ) async {
    try {
      await sendEphemeralToDevice(
        _client,
        devices,
        liveLocationPositionType,
        livePositionContent(
          roomId: share.roomId,
          shareId: share.shareId,
          position: position,
        ),
      ).timeout(_sendDeadline);
      return true;
    } catch (error) {
      logCaught('live location send', error.runtimeType);
      return false;
    }
  }

  void _settle() {
    _inFlight--;
    if (_inFlight > 0) return;
    _idle?.complete();
    _idle = null;
  }

  Future<void> _whenIdle() =>
      _inFlight == 0 ? Future.value() : (_idle ??= Completer()).future;

  void _onToDevice(ToDeviceEvent event) {
    if (event.type != liveLocationWatchType) return;
    final device = olmSenderDevice(_client, event);
    if (device == null) return;
    final message = parseLiveWatch(event.content);
    if (message == null) return;
    _endDue();
    final share = _active[message.roomId];
    if (share == null || !share.published) return;
    if (share.shareId != message.shareId) return;
    final room = _client.getRoomById(share.roomId);
    if (room == null) return;
    final key = _deviceKey(device);
    final ignored = _client.ignoredUsers.toSet();
    if (!message.active ||
        !isLiveLocationPeer(room, device, ignored: ignored)) {
      share.watchers.remove(key);
      share.firstSends.remove(key);
      _refreshMode();
      return;
    }
    if (!share.watchers.containsKey(key)) share.firstSends.add(key);
    share.watchers[key] = _Watcher(device, _now().add(liveWatchLifetime));
    _refreshMode();
    unawaited(_evaluate(share));
  }

  void _onTimelineEvent(Event event) {
    if (event.senderId != _client.userID) return;
    if (event.messageType != liveLocationMsgtype) return;
    final share = _active[event.room.id];
    if (share == null) return;
    if (event.content['share_id'] == share.shareId) {
      share.startEventIds.add(event.eventId);
    }
  }

  void _onSync(SyncUpdate update) {
    _endDue();
    final userId = _client.userID;
    if (userId == null) return;
    final ignoredChanged =
        update.accountData?.any((event) => event.type == _ignoredUserList) ??
        false;
    final changedUsers = {
      ...?update.deviceLists?.changed,
      ...?update.deviceLists?.left,
    };
    _unreachable.forgetUsers(changedUsers);
    final ignored = _client.ignoredUsers.toSet();
    for (final share in [..._active.values]) {
      final room = _client.getRoomById(share.roomId);
      if (room == null || room.membership != Membership.join) {
        unawaited(_endLocally(share));
        continue;
      }
      final roomUpdate = update.rooms?.join?[share.roomId];
      final events = [...?roomUpdate?.state, ...?roomUpdate?.timeline?.events];
      if (events.any(
        (event) =>
            event.type == EventTypes.Redaction &&
            share.startEventIds.contains(
              event.redacts ?? event.content['redacts'],
            ),
      )) {
        unawaited(stop(share.roomId));
        continue;
      }
      if (ignoredChanged ||
          events.any((event) => event.type == EventTypes.RoomMember) ||
          share.recipients.any(
            (device) => changedUsers.contains(device.userId),
          )) {
        share.recipientsStale = true;
      }
      _pruneWatchers(share, room, ignored);
      if (events.any(
        (event) =>
            event.type == liveLocationStateType &&
            event.stateKey == userId &&
            event.eventId != share.stateEventId,
      )) {
        if (share.published) {
          unawaited(_verifyStillOurs(share));
        } else {
          share.reverify = true;
        }
      }
    }
    _refreshMode();
    _sweep.sweep(update);
  }

  Future<void> _verifyStillOurs(_ActiveShare share) async {
    final userId = _client.userID;
    if (userId == null) return;
    if (share.verifying) {
      share.reverify = true;
      return;
    }
    share.verifying = true;
    try {
      final content = await _client.getRoomStateWithKey(
        share.roomId,
        liveLocationStateType,
        userId,
      );
      if (content['share_id'] != share.shareId ||
          content['device_id'] != _client.deviceID) {
        await _endLocally(share);
      }
    } on MatrixException catch (error) {
      if (error.error == MatrixError.M_NOT_FOUND) await _endLocally(share);
    } catch (error) {
      logCaught('live location check', error);
    } finally {
      share.verifying = false;
      if (share.reverify && _active[share.roomId] == share) {
        share.reverify = false;
        unawaited(_verifyStillOurs(share));
      }
    }
  }

  Future<void> _endLocally(_ActiveShare share) async {
    if (_active[share.roomId] != share) return;
    _active.remove(share.roomId);
    share.endTimer?.cancel();
    _publish();
    await _settleCapture();
  }
}

final liveLocationSharingProvider = Provider<LiveLocationSharing>((ref) {
  final client = ref.watch(matrixClientProvider);
  ref.watch(isLoggedInProvider);
  final sharing = LiveLocationSharing(
    client: client,
    capture: ref.watch(liveLocationCaptureProvider),
    isOffline: () => ref.read(isOfflineProvider).value ?? false,
  );
  ref.listen(isOfflineProvider, (previous, next) {
    if (becameOnline(previous, next)) sharing.onConnectivityRestored();
  });
  ref.onDispose(sharing.dispose);
  return sharing;
});
