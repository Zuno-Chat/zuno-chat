import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../errors/best_effort.dart';
import '../../errors/retry_backoff.dart';
import '../../matrix/bearer_authorization.dart';
import '../call_engine.dart';
import '../cloudflare/calls_module.dart';
import '../cloudflare/cloudflare_call_engine.dart';
import '../models/call_engine_status.dart';
import '../models/call_kind.dart';
import '../models/voip_participant_id.dart';
import 'active_room_call.dart';
import 'call_decline.dart';
import 'call_encryption_key_event.dart';
import 'call_member_state.dart';
import 'call_summary_message.dart';
import 'ice_servers.dart';

enum CallSessionRole { caller, callee }

enum CallSessionPhase { ringing, connecting, active, ended }

enum CallEndReason { hungUp, declinedByUs, declinedByThem, missed, failed }

const _ringTimeout = Duration(seconds: 45);
const _membershipTtl = Duration(seconds: 120);
const _membershipRefreshInterval = Duration(seconds: 50);
const _membershipDebounce = Duration(seconds: 1);
const _remoteLeftConfirmDelay = Duration(seconds: 2);
const _callFullMessage =
    'This call is full. Up to $maxCallParticipants people can join a call.';

class CallSession {
  final Room room;
  final String callId;
  final CallSessionRole role;
  final bool lowDataMode;
  CallKind kind;

  Client get client => room.client;
  String get _myUserId => client.userID!;
  String get _myDeviceId => client.deviceID!;

  CallEngine? _engine;
  CallEngine get engine => _engine!;

  CallSessionPhase _phase;
  final _phaseController = StreamController<CallSessionPhase>.broadcast();
  CallSessionPhase get phase => _phase;
  Stream<CallSessionPhase> get phaseStream => _phaseController.stream;

  CallEndReason? endReason;
  String? failedMessage;

  DateTime? _activeAt;
  Timer? _ringTimeoutTimer;
  Timer? _membershipRefreshTimer;
  StreamSubscription<SyncUpdate>? _syncSub;
  StreamSubscription<ToDeviceEvent>? _toDeviceSub;
  StreamSubscription<Event>? _declineSub;
  StreamSubscription<void>? _localStateSub;
  StreamSubscription<CallEngineStatus>? _statusSub;

  final Set<VoipParticipantId> _knownRemote = {};
  final Map<VoipParticipantId, String?> _knownRemoteSessions = {};
  bool _everHadRemote = false;
  bool get everHadRemote => _everHadRemote;

  final _remoteJoinedController = StreamController<void>.broadcast();
  Stream<void> get remoteJoinedStream => _remoteJoinedController.stream;

  Uint8List? _encryptionKey;
  bool get isEncrypted => _encryptionKey != null;

  final Map<VoipParticipantId, Uint8List> _pendingKeys = {};
  static const _maxPendingKeys = 8;

  String? _lastPublishedMembership;
  int? _joinedAtMs;
  Timer? _membershipDebounceTimer;
  Timer? _remoteLeftConfirmTimer;
  int _consecutiveEmptyReconciles = 0;

  @visibleForTesting
  final Future<CallEngine> Function()? engineBuilder;

  static const _defaultKeyRelayBaseDelay = Duration(milliseconds: 300);
  static const _defaultKeyRelayMaxDelay = Duration(seconds: 1);

  final Duration keyRelayBaseDelay;
  final Duration keyRelayMaxDelay;
  final Duration remoteLeftConfirmDelay;
  final http.Client? callsHttpClient;

  CallSession._({
    required this.room,
    required this.callId,
    required this.role,
    required this.kind,
    required this.lowDataMode,
    required this._phase,
    this.engineBuilder,
    this.keyRelayBaseDelay = _defaultKeyRelayBaseDelay,
    this.keyRelayMaxDelay = _defaultKeyRelayMaxDelay,
    this.remoteLeftConfirmDelay = _remoteLeftConfirmDelay,
    this.callsHttpClient,
  });

  void _setPhase(CallSessionPhase phase) {
    _phase = phase;
    _phaseController.add(phase);
  }

  Future<CallEngine> _buildEngine() async {
    if (engineBuilder case final build?) return build();
    return CloudflareCallEngine(
      baseUri: cloudflareCallsBaseUri(client),
      authorization: () => bearerAuthorization(client),
      kind: kind,
      iceServers: resolveIceServers(client, httpClient: callsHttpClient),
      lowDataMode: lowDataMode,
      httpClient: callsHttpClient,
    );
  }

  static CallSession startOutgoing(
    Room room,
    CallKind kind, {
    bool lowDataMode = false,
    @visibleForTesting Future<CallEngine> Function()? engineBuilder,
    @visibleForTesting Duration? keyRelayBaseDelay,
    @visibleForTesting Duration? keyRelayMaxDelay,
    @visibleForTesting Duration? remoteLeftConfirmDelay,
    @visibleForTesting http.Client? callsHttpClient,
  }) {
    final session = CallSession._(
      room: room,
      callId: room.client.generateUniqueTransactionId(),
      role: CallSessionRole.caller,
      kind: kind,
      lowDataMode: lowDataMode,
      phase: CallSessionPhase.connecting,
      engineBuilder: engineBuilder,
      keyRelayBaseDelay: keyRelayBaseDelay ?? _defaultKeyRelayBaseDelay,
      keyRelayMaxDelay: keyRelayMaxDelay ?? _defaultKeyRelayMaxDelay,
      remoteLeftConfirmDelay: remoteLeftConfirmDelay ?? _remoteLeftConfirmDelay,
      callsHttpClient: callsHttpClient,
    );
    session._encryptionKey = _generateCallKey();
    session._listenForDecline();
    unawaited(session._startOutgoingConnect());
    return session;
  }

  static Uint8List _generateCallKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
  }

  void _listenForDecline() {
    _declineSub = client.onTimelineEvent.stream.listen(_handleDeclineEvent);
  }

  void _handleDeclineEvent(Event event) {
    if (event.room.id != room.id) return;
    if (event.messageType != callDeclineMsgtype) return;
    if (event.content.tryGet<String>('call_id') != callId) return;
    if (_phase == CallSessionPhase.ended) return;
    if (event.senderId == _myUserId) return;
    if (_everHadRemote) return;
    if (_otherJoinedMemberCount() != 1) return;
    endReason = CallEndReason.declinedByThem;
    unawaited(hangUp());
  }

  int _otherJoinedMemberCount() => room
      .getParticipants(const [Membership.join])
      .where((user) => user.id != _myUserId)
      .length;

  Future<void> _startOutgoingConnect() async {
    try {
      await room.sendEvent({
        'msgtype': callInviteMsgtype,
        'body': kind == CallKind.video
            ? 'Incoming video call'
            : 'Incoming voice call',
        'call_id': callId,
        'kind': kind.name,
      });
      await _connect();
      _startRingTimeout();
    } catch (_) {
      if (phase != CallSessionPhase.ended) {
        endReason = CallEndReason.failed;
        _setPhase(CallSessionPhase.ended);
      }
    }
  }

  static CallSession forIncoming({
    required Room room,
    required String callId,
    required CallKind kind,
    bool lowDataMode = false,
    @visibleForTesting Future<CallEngine> Function()? engineBuilder,
    @visibleForTesting Uint8List? initialEncryptionKeyForTesting,
    @visibleForTesting Duration? keyRelayBaseDelay,
    @visibleForTesting Duration? keyRelayMaxDelay,
    @visibleForTesting Duration? remoteLeftConfirmDelay,
    @visibleForTesting http.Client? callsHttpClient,
  }) {
    return CallSession._(
      room: room,
      callId: callId,
      role: CallSessionRole.callee,
      kind: kind,
      lowDataMode: lowDataMode,
      phase: CallSessionPhase.ringing,
      engineBuilder: engineBuilder,
      keyRelayBaseDelay: keyRelayBaseDelay ?? _defaultKeyRelayBaseDelay,
      keyRelayMaxDelay: keyRelayMaxDelay ?? _defaultKeyRelayMaxDelay,
      remoteLeftConfirmDelay: remoteLeftConfirmDelay ?? _remoteLeftConfirmDelay,
      callsHttpClient: callsHttpClient,
    ).._encryptionKey = initialEncryptionKeyForTesting;
  }

  Future<void> accept() async {
    if (isCallFull(room, callId, excludeUserId: _myUserId)) {
      _markCallFull();
      _setPhase(CallSessionPhase.ended);
      return;
    }
    await _connect();
  }

  void _markCallFull() {
    failedMessage = _callFullMessage;
    endReason = CallEndReason.failed;
  }

  Future<void> decline() async {
    await declineCall(room, callId);
    endReason = CallEndReason.declinedByUs;
    _setPhase(CallSessionPhase.ended);
  }

  Future<void>? _permissionsFuture;

  Future<void> ensurePermissions() =>
      _permissionsFuture ??= _requestPermissions();

  Future<void> _requestPermissions() async {
    final needed = [
      Permission.microphone,
      if (kind == CallKind.video) Permission.camera,
    ];
    final statuses = await needed.request();
    if (statuses[Permission.microphone] != PermissionStatus.granted) {
      throw StateError('Microphone permission is required for calls');
    }
  }

  Future<void> _connect() async {
    _setPhase(CallSessionPhase.connecting);
    try {
      final results = await Future.wait<Object?>(
        [ensurePermissions(), _buildEngine()],
        eagerError: true,
        cleanUp: (value) {
          if (value is CallEngine) value.dispose();
        },
      );
      final built = results[1] as CallEngine;
      _engine = built;
      if (await _abandonEngineIfEnded(built)) return;

      if (_encryptionKey case final key?) await built.setEncryptionKey(key);
      await built.join();
      if (await _abandonEngineIfEnded(built)) return;

      _statusSub = built.statusStream.listen((status) {
        if (status != CallEngineStatus.failed) return;
        if (_phase == CallSessionPhase.ended) return;
        failedMessage = 'Connection lost';
        endReason = CallEndReason.failed;
        unawaited(hangUp());
      });
      _toDeviceSub = client.onToDeviceEvent.stream.listen(_handleToDeviceEvent);
      _localStateSub = built.localStateChangedStream.listen(
        (_) => unawaited(
          runBestEffort(_publishOwnMembership, label: 'republish membership'),
        ),
      );

      await _publishOwnMembership();
      if (_phase == CallSessionPhase.ended) return;
      _membershipRefreshTimer = Timer.periodic(
        _membershipRefreshInterval,
        (_) => _publishOwnMembership(force: true),
      );
      _syncSub = client.onSync.stream.listen(
        (_) => _reconcileRemoteMemberships(),
      );
      _reconcileRemoteMemberships();
      _setPhase(CallSessionPhase.active);
      _activeAt = DateTime.now();
    } catch (e, s) {
      debugPrint('[CallSession] _connect failed: $e\n$s');
      if (_hangUp == null) {
        failedMessage =
            e is MatrixException && e.error == MatrixError.M_FORBIDDEN
            ? 'You do not have permission to start calls in this room'
            : 'Call did not connect';
        endReason = CallEndReason.failed;
        if (_engine case final engine?) {
          await _tearDownEngine(engine, 'a failed connect');
        }
      }
      _setPhase(CallSessionPhase.ended);
      rethrow;
    }
  }

  bool _engineTornDown = false;

  Future<bool> _abandonEngineIfEnded(CallEngine engine) async {
    if (_hangUp == null && _phase != CallSessionPhase.ended) return false;
    await _tearDownEngine(engine, 'a hangup during connect');
    return true;
  }

  Future<void> _tearDownEngine(CallEngine engine, String why) async {
    if (_engineTornDown) return;
    _engineTornDown = true;
    await runBestEffort(engine.leave, label: 'leave engine after $why');
    await runBestEffort(engine.dispose, label: 'dispose engine after $why');
  }

  void _startRingTimeout() {
    _ringTimeoutTimer = Timer(_ringTimeout, () {
      if (_knownRemote.isEmpty) hangUp();
    });
  }

  void _handleToDeviceEvent(ToDeviceEvent event) {
    if (_encryptionKey != null) return;
    if (event.type != callEncryptionKeyEventType) return;

    final encryptedContent = event.encryptedContent;
    if (encryptedContent == null) return;

    final senderKey = encryptedContent['sender_key'];
    if (senderKey is! String) return;
    final device = client.getUserDeviceKeysByCurve25519Key(senderKey);
    if (device == null || device.blocked) return;
    if (device.userId != event.senderId) return;

    final key = parseCallEncryptionKeyContent(
      content: event.content,
      callId: callId,
    );
    if (key == null) return;

    final deviceId = device.deviceId;
    if (deviceId == null) return;
    final id = VoipParticipantId(userId: device.userId, deviceId: deviceId);
    if (!_currentCallParticipants().contains(id)) {
      if (_pendingKeys.length < _maxPendingKeys) _pendingKeys[id] = key;
      return;
    }
    _applyEncryptionKey(key);
  }

  void _applyEncryptionKey(Uint8List key) {
    if (_encryptionKey != null) return;
    _encryptionKey = key;
    _pendingKeys.clear();
    if (_engine case final engine?) {
      unawaited(_applyEncryptionKeyToEngine(engine, key));
    }
  }

  Future<void> _applyEncryptionKeyToEngine(
    CallEngine engine,
    Uint8List key,
  ) async {
    try {
      await engine.setEncryptionKey(key);
    } catch (e, s) {
      debugPrint('[CallSession] applying the call key failed: $e\n$s');
      if (_phase == CallSessionPhase.ended) return;
      failedMessage = 'Call did not connect';
      endReason = CallEndReason.failed;
      await hangUp();
    }
  }

  Set<VoipParticipantId> _currentCallParticipants() {
    final states = room.states[callMemberEventType] ?? const {};
    return {
      for (final entry in states.entries)
        for (final membership in parseRtcMemberships(entry.value.content))
          if (membership.callId == callId && !membership.isExpired)
            VoipParticipantId(userId: entry.key, deviceId: membership.deviceId),
    };
  }

  static const _keyRelayAttempts = 3;

  Future<void> _sendEncryptionKeyTo(VoipParticipantId id) async {
    final key = _encryptionKey;
    if (key == null) return;
    try {
      await retryWithBackoff(
        () => _sendEncryptionKeyOnce(id, key),
        label: 'call key relay to $id',
        maxAttempts: _keyRelayAttempts,
        baseDelay: keyRelayBaseDelay,
        maxDelay: keyRelayMaxDelay,
        retryIf: (_) => _phase != CallSessionPhase.ended,
      );
    } catch (_) {}
  }

  Future<void> _sendEncryptionKeyOnce(
    VoipParticipantId id,
    Uint8List key,
  ) async {
    await client.updateUserDeviceKeys(additionalUsers: {id.userId});
    final deviceKeys =
        client.userDeviceKeys[id.userId]?.deviceKeys[id.deviceId];
    if (deviceKeys == null) throw StateError('No device keys yet for $id');
    await client.sendToDeviceEncrypted(
      [deviceKeys],
      callEncryptionKeyEventType,
      buildCallEncryptionKeyContent(callId: callId, key: key),
    );
  }

  Future<void> refreshMembership() async {
    if (_phase == CallSessionPhase.ended || _engine == null) return;
    final pendingTrailing = _membershipDebounceTimer;
    if (pendingTrailing == null) {
      _publishMembershipBestEffort();
    } else {
      pendingTrailing.cancel();
    }
    _membershipDebounceTimer = Timer(_membershipDebounce, () {
      _membershipDebounceTimer = null;
      if (_phase == CallSessionPhase.ended) return;
      _publishMembershipBestEffort();
    });
  }

  void _publishMembershipBestEffort() {
    unawaited(
      runBestEffort(_publishOwnMembership, label: 'refresh membership'),
    );
  }

  Future<void> _publishOwnMembership({bool force = false}) async {
    final foci = engine.localFociInfo;
    if (foci == null) return;
    final fingerprint = jsonEncode({'kind': kind.name, 'foci': foci});
    if (!force && fingerprint == _lastPublishedMembership) return;
    final membership = RtcMembership(
      callId: callId,
      deviceId: _myDeviceId,
      kind: kind.name,
      expiresAtMs: DateTime.now().add(_membershipTtl).millisecondsSinceEpoch,
      createdAtMs: _joinedAtMs ??= DateTime.now().millisecondsSinceEpoch,
      fociActive: foci,
    );
    await client.setRoomStateWithKey(room.id, callMemberEventType, _myUserId, {
      'memberships': [membership.toJson()],
    });
    _lastPublishedMembership = fingerprint;
  }

  Future<void> _clearOwnMembership() async {
    try {
      await client.setRoomStateWithKey(
        room.id,
        callMemberEventType,
        _myUserId,
        {'memberships': <Object?>[]},
      );
    } catch (_) {}
  }

  void _reconcileRemoteMemberships() {
    final eng = _engine;
    if (eng == null) return;
    final states = room.states[callMemberEventType] ?? const {};
    final seenThisPass = <VoipParticipantId>{};

    for (final entry in states.entries) {
      final userId = entry.key;
      if (userId == _myUserId) continue;
      for (final membership in parseRtcMemberships(entry.value.content)) {
        if (membership.callId != callId) continue;
        final id = VoipParticipantId(
          userId: userId,
          deviceId: membership.deviceId,
        );
        seenThisPass.add(id);
        if (_pendingKeys.remove(id) case final pending?) {
          _applyEncryptionKey(pending);
        }
        final remoteSessionId = membership.fociActive['sessionId'] as String?;
        final isNewDevice = _knownRemote.add(id);
        if (isNewDevice || _knownRemoteSessions[id] != remoteSessionId) {
          _knownRemoteSessions[id] = remoteSessionId;
          unawaited(_sendEncryptionKeyTo(id));
        }
        if (!_everHadRemote) {
          _everHadRemote = true;
          if (!_remoteJoinedController.isClosed) {
            _remoteJoinedController.add(null);
          }
        }
        _ringTimeoutTimer?.cancel();
        eng.updateRemoteParticipant(id, membership.fociActive);
      }
    }

    if (_hangUp == null && isOverCallCapacity(room, callId, _myUserId)) {
      _markCallFull();
      unawaited(hangUp());
      return;
    }

    for (final id in _knownRemote.difference(seenThisPass)) {
      eng.removeRemoteParticipant(id);
      _knownRemote.remove(id);
      _knownRemoteSessions.remove(id);
    }

    if (seenThisPass.isNotEmpty) {
      _consecutiveEmptyReconciles = 0;
      _remoteLeftConfirmTimer?.cancel();
      _remoteLeftConfirmTimer = null;
      return;
    }
    _consecutiveEmptyReconciles++;
    if (!_everHadRemote || _phase != CallSessionPhase.active) return;
    if (_consecutiveEmptyReconciles >= 2) {
      unawaited(hangUp());
      return;
    }
    _remoteLeftConfirmTimer ??= Timer(remoteLeftConfirmDelay, () {
      _remoteLeftConfirmTimer = null;
      _reconcileRemoteMemberships();
    });
  }

  void _cancelTimers() {
    _ringTimeoutTimer?.cancel();
    _membershipRefreshTimer?.cancel();
    _membershipDebounceTimer?.cancel();
    _remoteLeftConfirmTimer?.cancel();
  }

  List<StreamSubscription<Object?>?> get _subscriptions => [
    _syncSub,
    _toDeviceSub,
    _declineSub,
    _localStateSub,
    _statusSub,
  ];

  Future<void>? _hangUp;

  Future<void> hangUp() => _hangUp ??= _hangUpOnce();

  Future<void> _hangUpOnce() async {
    if (_phase == CallSessionPhase.ended) return;
    final wasRinging = _phase == CallSessionPhase.ringing;
    final wasUnanswered = !_everHadRemote;
    final othersStillPresent = _knownRemote.isNotEmpty;

    _cancelTimers();
    _pendingKeys.clear();
    for (final subscription in _subscriptions) {
      await subscription?.cancel();
    }

    await _clearOwnMembership();
    if (_engine case final engine? when !_engineTornDown) {
      _engineTornDown = true;
      await engine.leave();
      engine.dispose();
    }

    final reason = endReason ??= wasRinging || wasUnanswered
        ? CallEndReason.missed
        : CallEndReason.hungUp;
    _setPhase(CallSessionPhase.ended);

    if (!othersStillPresent) {
      final status = switch (reason) {
        CallEndReason.missed => CallSummaryStatus.missed,
        CallEndReason.declinedByThem => CallSummaryStatus.declined,
        _ => CallSummaryStatus.ended,
      };
      final duration = _activeAt == null
          ? 0
          : DateTime.now().difference(_activeAt!).inMilliseconds;
      await room.sendEvent(
        CallSummary(
          callId: callId,
          kind: kind.name,
          status: status,
          durationMs: duration,
        ).toMessageContent(),
      );
    }
  }

  void dispose() {
    _cancelTimers();
    _pendingKeys.clear();
    for (final subscription in _subscriptions) {
      unawaited(subscription?.cancel());
    }
    _phaseController.close();
    _remoteJoinedController.close();
  }
}
