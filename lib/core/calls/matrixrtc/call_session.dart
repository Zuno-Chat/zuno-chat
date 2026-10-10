import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show ValueListenable, visibleForTesting;
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState, WidgetsBinding;
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../errors/best_effort.dart';
import '../../errors/caught_errors.dart';
import '../../errors/retry_backoff.dart';
import '../../matrix/bearer_authorization.dart';
import '../../matrix/olm_sender.dart';
import '../../platform/platform_capabilities.dart';
import '../call_engine.dart';
import '../cloudflare/calls_module.dart';
import '../cloudflare/cloudflare_call_engine.dart';
import '../models/call_engine_status.dart';
import '../models/call_kind.dart';
import '../models/voip_participant_id.dart';
import '../notifications/call_notification_service.dart';
import 'active_room_call.dart';
import 'call_decline.dart';
import 'call_encryption_key_event.dart';
import 'call_member_state.dart';
import 'call_membership_writer.dart';
import 'call_summary_message.dart';
import 'ice_servers.dart';

enum CallSessionRole { caller, callee }

enum CallSessionPhase { ringing, connecting, active, ended }

enum CallEndReason { hungUp, declinedByThem, missed, failed }

const _ringTimeout = Duration(seconds: 45);
const _membershipTtl = Duration(seconds: 120);
const _membershipRefreshInterval = Duration(seconds: 50);
const _membershipDebounce = Duration(seconds: 1);
const _remoteLeftConfirmDelay = Duration(seconds: 2);
const microphoneUnavailableMessage =
    'Allow Zuno to use the microphone, then call back.';
const callDidNotConnectMessage = 'Call did not connect';
const _foregroundWait = Duration(seconds: 3);
const _callFullMessage =
    'This call is full. Up to $maxCallParticipants people can join a call.';

class CallSession {
  final Client client;
  final String _roomId;
  Room _room;
  bool _roomSeen;
  final String callId;
  final CallSessionRole role;
  final bool lowDataMode;
  CallKind kind;

  Room get room {
    final live = client.getRoomById(_roomId);
    if (live == null) return _room;
    _roomSeen = true;
    return _room = live;
  }

  String get _myUserId => client.userID!;
  String get _myDeviceId => client.deviceID!;

  CallEngine? _engine;
  Future<void>? _engineTeardown;

  CallEngine get engine {
    if (_engine case final built?) return built;
    final built = _engine = _buildEngine();
    if (_engineTeardown != null) {
      unawaited(_releaseEngine(built, 'a call that had already ended'));
    }
    return built;
  }

  CallSessionPhase _phase;
  final _phaseController = StreamController<CallSessionPhase>.broadcast();
  CallSessionPhase get phase => _phase;
  Stream<CallSessionPhase> get phaseStream => _phaseController.stream;

  CallEndReason? endReason;
  String? failedMessage;

  DateTime? _activeAt;
  Timer? _ringTimeoutTimer;
  Timer? _membershipRefreshTimer;
  StreamSubscription<SyncUpdate>? _roomSub;
  StreamSubscription<SyncUpdate>? _syncSub;
  StreamSubscription<ToDeviceEvent>? _toDeviceSub;
  StreamSubscription<Event>? _declineSub;
  StreamSubscription<void>? _localStateSub;
  StreamSubscription<CallEngineStatus>? _statusSub;
  StreamSubscription<LoginState>? _loginSub;
  bool _endedLocally = false;

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

  bool _membershipLive = false;
  bool _membershipRequested = false;
  String? _lastPublishedMembership;
  String? _membershipEventId;
  int? _joinedAtMs;
  Timer? _membershipDebounceTimer;
  Timer? _remoteLeftConfirmTimer;
  int _consecutiveEmptyReconciles = 0;

  @visibleForTesting
  final CallEngine Function()? engineBuilder;

  static const _defaultKeyRelayBaseDelay = Duration(milliseconds: 300);
  static const _defaultKeyRelayMaxDelay = Duration(seconds: 1);

  final Duration keyRelayBaseDelay;
  final Duration keyRelayMaxDelay;
  final Duration ringTimeout;
  final http.Client? callsHttpClient;
  final ValueListenable<bool> _pictureInPictureCamera;

  CallSession._({
    required Room room,
    required this.callId,
    required this.role,
    required this.kind,
    required this.lowDataMode,
    required this._phase,
    this.engineBuilder,
    this.keyRelayBaseDelay = _defaultKeyRelayBaseDelay,
    this.keyRelayMaxDelay = _defaultKeyRelayMaxDelay,
    this.ringTimeout = _ringTimeout,
    this.callsHttpClient,
    ValueListenable<bool>? pictureInPictureCamera,
  }) : client = room.client,
       _roomId = room.id,
       _room = room,
       _roomSeen = room.client.getRoomById(room.id) != null,
       _pictureInPictureCamera =
           pictureInPictureCamera ??
           CallNotificationService.instance.pictureInPictureCamera;

  void _setPhase(CallSessionPhase phase) {
    if (_phase == CallSessionPhase.ended) return;
    _phase = phase;
    if (phase == CallSessionPhase.ended) _releaseListeners();
    _phaseController.add(phase);
  }

  bool get _ending => _hangUp != null || _phase == CallSessionPhase.ended;

  void _followSignInAndRoom() {
    _loginSub = client.onLoginStateChanged.stream.listen((state) {
      if (state == LoginState.loggedOut) unawaited(_endLocally());
    });
    _roomSub = client.onSync.stream.listen((update) {
      if (_leftRoom(update)) unawaited(_endLocally());
    });
  }

  Future<void> _endLocally() async {
    if (_phase == CallSessionPhase.ended || _endedLocally) return;
    _endedLocally = true;
    endReason ??= CallEndReason.hungUp;
    await _end('the call ending locally');
  }

  Future<void> _end(String why) async {
    _releaseListeners();
    await _tearDownEngine(why);
    _setPhase(CallSessionPhase.ended);
  }

  CallEngine _buildEngine() {
    if (engineBuilder case final build?) return build();
    return CloudflareCallEngine(
      baseUri: () => cloudflareCallsBaseUri(client),
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
    @visibleForTesting CallEngine Function()? engineBuilder,
    @visibleForTesting Duration? keyRelayBaseDelay,
    @visibleForTesting Duration? keyRelayMaxDelay,
    @visibleForTesting Duration? ringTimeout,
    @visibleForTesting http.Client? callsHttpClient,
    @visibleForTesting ValueListenable<bool>? pictureInPictureCamera,
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
      ringTimeout: ringTimeout ?? _ringTimeout,
      callsHttpClient: callsHttpClient,
      pictureInPictureCamera: pictureInPictureCamera,
    );
    session._encryptionKey = _generateCallKey();
    session._listenForDecline();
    session._followSignInAndRoom();
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
    if (event.room.id != _roomId) return;
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

  Future<String?>? _invite;

  Future<void> _startOutgoingConnect() async {
    final String? invite;
    try {
      await ensurePermissions();
      if (_ending) return;
      _startLocalMedia().ignore();
      invite = await (_invite = _sendInvite());
    } catch (e, s) {
      if (!_shownToUser(e)) reportCaught('start an outgoing call', e, s);
      await _failBeforeRinging(e);
      return;
    }
    if (invite == null) {
      final unsent = StateError('The call invite was not sent');
      reportCaught('send the call invite', unsent);
      await _failBeforeRinging(unsent);
      return;
    }
    if (_ending) return;
    try {
      await _connect();
      _startRingTimeout();
    } catch (e, s) {
      if (!_shownToUser(e)) reportCaught('connect an outgoing call', e, s);
      await hangUp();
    }
  }

  Future<String?> _sendInvite() => room.sendEvent({
    'msgtype': callInviteMsgtype,
    'body': kind == CallKind.video
        ? 'Incoming video call'
        : 'Incoming voice call',
    'call_id': callId,
    'kind': kind.name,
  }, displayPendingEvent: false);

  Future<bool> _inviteDelivered() async {
    final invite = _invite;
    if (invite == null) return false;
    try {
      return await invite != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> _failBeforeRinging(Object error) async {
    if (_ending) return;
    failedMessage = _failureMessage(error);
    endReason = CallEndReason.failed;
    await _end('a call that never rang');
  }

  Future<void>? _localMedia;

  Future<void> _startLocalMedia() => _localMedia ??= _openLocalMedia();

  Future<void> _openLocalMedia() async {
    await ensurePermissions();
    if (_ending) return;
    final built = engine;
    if (_cameraRefused) await built.setCameraEnabled(false);
    if (_ending) return;
    await _followAppLifecycle(built);
    if (_ending) return;
    await built.startLocalMedia();
  }

  static CallSession forIncoming({
    required Room room,
    required String callId,
    required CallKind kind,
    bool lowDataMode = false,
    @visibleForTesting CallEngine Function()? engineBuilder,
    @visibleForTesting Uint8List? initialEncryptionKeyForTesting,
    @visibleForTesting Duration? keyRelayBaseDelay,
    @visibleForTesting Duration? keyRelayMaxDelay,
    @visibleForTesting http.Client? callsHttpClient,
    @visibleForTesting ValueListenable<bool>? pictureInPictureCamera,
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
        callsHttpClient: callsHttpClient,
        pictureInPictureCamera: pictureInPictureCamera,
      )
      .._encryptionKey = initialEncryptionKeyForTesting
      .._followSignInAndRoom();
  }

  Future<void> accept() async {
    if (isCallFull(room, callId, excludeUserId: _myUserId)) {
      _markCallFull();
      await _end('a call that was full');
      return;
    }
    try {
      await _connect();
    } catch (e, s) {
      if (!_shownToUser(e)) reportCaught('accept a call', e, s);
      await hangUp();
      rethrow;
    }
  }

  void _markCallFull() {
    failedMessage = _callFullMessage;
    endReason = CallEndReason.failed;
  }

  Future<void>? _permissionsFuture;
  bool _cameraRefused = false;

  Future<void> ensurePermissions() =>
      _permissionsFuture ??= _requestPermissions();

  Future<void> _requestPermissions() async {
    final video = kind == CallKind.video;
    final needed = [Permission.microphone, if (video) Permission.camera];
    if (ambientCapabilities.callKit) await _awaitMicrophonePrompt();
    final statuses = await needed.request();
    if (statuses[Permission.microphone] != PermissionStatus.granted) {
      throw const MicrophoneUnavailable();
    }
    _cameraRefused =
        video && statuses[Permission.camera] != PermissionStatus.granted;
  }

  Future<void> _awaitMicrophonePrompt() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return;
    if (status.isPermanentlyDenied || !await _reachesForeground()) {
      throw const MicrophoneUnavailable();
    }
  }

  Future<bool> _reachesForeground() async {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      return true;
    }
    final resumed = Completer<bool>();
    final listener = AppLifecycleListener(
      onResume: () {
        if (!resumed.isCompleted) resumed.complete(true);
      },
    );
    try {
      return await resumed.future.timeout(
        _foregroundWait,
        onTimeout: () => false,
      );
    } finally {
      listener.dispose();
    }
  }

  Future<void> _connect() async {
    _setPhase(CallSessionPhase.connecting);
    try {
      await _startLocalMedia();
      if (await _abandonEngineIfEnded()) return;

      final built = engine;
      if (_encryptionKey case final key?) await built.setEncryptionKey(key);
      if (await _abandonEngineIfEnded()) return;
      await built.join();
      if (await _abandonEngineIfEnded()) return;

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
      _membershipLive = true;

      await _publishOwnMembership();
      if (_ending) return;
      _membershipRefreshTimer = Timer.periodic(
        _membershipRefreshInterval,
        (_) => _publishMembershipBestEffort(force: true),
      );
      _syncSub = client.onSync.stream.listen(
        (_) => _reconcileRemoteMemberships(),
      );
      _reconcileRemoteMemberships();
      _setPhase(CallSessionPhase.active);
      _activeAt = DateTime.now();
    } catch (e) {
      if (_hangUp == null) {
        failedMessage = _failureMessage(e);
        endReason = CallEndReason.failed;
      }
      rethrow;
    }
  }

  static bool _isForbidden(Object error) =>
      error is MatrixException && error.error == MatrixError.M_FORBIDDEN;

  static bool _shownToUser(Object error) =>
      _isForbidden(error) || error is MicrophoneUnavailable;

  static String _failureMessage(Object error) => switch (error) {
    _ when _isForbidden(error) =>
      'You do not have permission to start calls in this room',
    MicrophoneUnavailable() => microphoneUnavailableMessage,
    _ => callDidNotConnectMessage,
  };

  AppLifecycleListener? _lifecycleListener;
  void Function()? _pictureInPictureListener;
  bool? _engineInBackground;

  Future<void> _followAppLifecycle(CallEngine engine) async {
    bool hidden(AppLifecycleState? state) => switch (state) {
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached => true,
      _ => false,
    };

    Future<void> tell(bool inBackground) async {
      if (_engineInBackground == inBackground) return;
      _engineInBackground = inBackground;
      await runBestEffort(
        () => engine.setAppInBackground(inBackground),
        label: 'tell the engine the app is in the background: $inBackground',
      );
    }

    var appHidden = hidden(WidgetsBinding.instance.lifecycleState);
    bool inBackground() => appHidden && !_pictureInPictureCamera.value;

    _stopFollowingAppLifecycle();
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.inactive) return;
        appHidden = hidden(state);
        unawaited(tell(inBackground()));
      },
    );
    void onPictureInPicture() => unawaited(tell(inBackground()));
    _pictureInPictureListener = onPictureInPicture;
    _pictureInPictureCamera.addListener(onPictureInPicture);
    await tell(inBackground());
  }

  void _stopFollowingAppLifecycle() {
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    final listener = _pictureInPictureListener;
    if (listener != null) _pictureInPictureCamera.removeListener(listener);
    _pictureInPictureListener = null;
  }

  Future<bool> _abandonEngineIfEnded() async {
    if (!_ending) return false;
    await _tearDownEngine('a hangup during connect');
    return true;
  }

  Future<void> _tearDownEngine(String why) =>
      _engineTeardown ??= _tearDownEngineOnce(why);

  Future<void> _tearDownEngineOnce(String why) async {
    _stopFollowingAppLifecycle();
    if (_engine case final built?) await _releaseEngine(built, why);
  }

  Future<void> _releaseEngine(CallEngine built, String why) async {
    await runBestEffort(built.leave, label: 'leave engine after $why');
    await runBestEffort(built.dispose, label: 'dispose engine after $why');
  }

  void _startRingTimeout() {
    _ringTimeoutTimer = Timer(ringTimeout, () {
      if (_knownRemote.isEmpty) hangUp();
    });
  }

  void _handleToDeviceEvent(ToDeviceEvent event) {
    if (_encryptionKey != null) return;
    if (event.type != callEncryptionKeyEventType) return;

    final device = olmSenderDevice(client, event);
    if (device == null) return;

    final key = parseCallEncryptionKeyContent(
      content: event.content,
      callId: callId,
    );
    if (key == null) return;

    final id = VoipParticipantId(
      userId: device.userId,
      deviceId: device.deviceId!,
    );
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
      reportCaught('apply the call key', e, s);
      if (_phase == CallSessionPhase.ended) return;
      failedMessage = callDidNotConnectMessage;
      endReason = CallEndReason.failed;
      await hangUp();
    }
  }

  Set<VoipParticipantId> _currentCallParticipants() {
    final states = room.states[callMemberEventType] ?? const {};
    return {
      for (final entry in states.entries)
        for (final membership in parseRtcMemberships(entry.value.content))
          if (membership.callId == callId)
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
        label: 'call key relay',
        maxAttempts: _keyRelayAttempts,
        baseDelay: keyRelayBaseDelay,
        maxDelay: keyRelayMaxDelay,
        retryIf: (_) => _phase != CallSessionPhase.ended,
      );
    } catch (e, s) {
      if (_phase == CallSessionPhase.ended) return;
      reportCaught('relay the call key', e, s);
    }
  }

  Future<void> _sendEncryptionKeyOnce(
    VoipParticipantId id,
    Uint8List key,
  ) async {
    await client.updateUserDeviceKeys(additionalUsers: {id.userId});
    final deviceKeys =
        client.userDeviceKeys[id.userId]?.deviceKeys[id.deviceId];
    if (deviceKeys == null) throw StateError('No device keys yet');
    await client.sendToDeviceEncrypted(
      [deviceKeys],
      callEncryptionKeyEventType,
      buildCallEncryptionKeyContent(callId: callId, key: key),
    );
  }

  Future<void> refreshMembership() async {
    if (!_membershipLive || _ending) return;
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

  void _publishMembershipBestEffort({bool force = false}) {
    unawaited(
      runBestEffort(
        () => _publishOwnMembership(force: force),
        label: 'refresh membership',
      ),
    );
  }

  Future<void> _publishOwnMembership({bool force = false}) async {
    if (!_membershipLive || _ending) return;
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
    _membershipRequested = true;
    _membershipEventId = await writeOwnCallMembership(client, _roomId, {
      'memberships': [membership.toJson()],
    });
    _lastPublishedMembership = fingerprint;
  }

  Future<void> _clearOwnMembership() => runBestEffort(
    () => writeOwnCallMembership(client, _roomId, {'memberships': <Object?>[]}),
    label: 'clear our call membership',
  );

  bool _leftRoom(SyncUpdate update) {
    if (update.rooms?.leave?.containsKey(_roomId) ?? false) return true;
    final live = client.getRoomById(_roomId);
    if (live == null) return _roomSeen && update.nextBatch.isNotEmpty;
    return live.membership == Membership.leave ||
        live.membership == Membership.ban;
  }

  void _reconcileRemoteMemberships() {
    final eng = _engine;
    if (eng == null) return;
    if (_roomSeen && client.getRoomById(_roomId) == null) return;
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
    _remoteLeftConfirmTimer ??= Timer(_remoteLeftConfirmDelay, () {
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
    _roomSub,
    _syncSub,
    _toDeviceSub,
    _declineSub,
    _localStateSub,
    _statusSub,
    _loginSub,
  ];

  void _releaseListeners() {
    _cancelTimers();
    _stopFollowingAppLifecycle();
    _pendingKeys.clear();
    for (final subscription in _subscriptions) {
      unawaited(subscription?.cancel());
    }
  }

  Future<void>? _hangUp;
  bool _endedByUser = false;
  bool _summarized = false;

  bool get endedByUser => _endedByUser;

  Future<void> hangUp({bool byUser = false, bool summarized = false}) {
    if (_hangUp case final pending?) return pending;
    _endedByUser = byUser;
    _summarized = summarized;
    return _hangUp = _hangUpOnce();
  }

  Future<void> _hangUpOnce() async {
    if (_phase == CallSessionPhase.ended) return;
    final wasRinging = _phase == CallSessionPhase.ringing;
    final wasUnanswered = !_everHadRemote;
    final reason = endReason ??= wasRinging || wasUnanswered
        ? CallEndReason.missed
        : CallEndReason.hungUp;
    final durationMs = switch (_activeAt) {
      final activeAt? => DateTime.now().difference(activeAt).inMilliseconds,
      null => 0,
    };

    await _end('a hang-up');
    if (_endedLocally) return;
    await Future.wait([
      if (_membershipRequested) _clearOwnMembership(),
      if (!_summarized)
        _sendEndNotice(
          reason,
          wasUnanswered: wasUnanswered,
          durationMs: durationMs,
        ),
    ]);
  }

  Future<void> _sendEndNotice(
    CallEndReason reason, {
    required bool wasUnanswered,
    required int durationMs,
  }) async {
    if (role == CallSessionRole.callee && !_membershipRequested) {
      if (reason == CallEndReason.failed) return;
      await runBestEffort(
        () => declineCall(room, callId),
        label: 'decline a call we never joined',
      );
      return;
    }
    if (role == CallSessionRole.caller && !await _inviteDelivered()) return;
    if (_othersStillInCall()) return;
    final status = switch (reason) {
      CallEndReason.declinedByThem => CallSummaryStatus.declined,
      _ when wasUnanswered => CallSummaryStatus.missed,
      CallEndReason.missed => CallSummaryStatus.missed,
      _ => CallSummaryStatus.ended,
    };
    await runBestEffort(
      () => room.sendEvent(
        CallSummary(
          callId: callId,
          kind: kind.name,
          status: status,
          durationMs: durationMs,
        ).toMessageContent(membershipEventId: _membershipEventId),
        displayPendingEvent: false,
      ),
      label: 'post the call summary',
    );
  }

  bool _othersStillInCall() => _currentCallParticipants().any(
    (id) => id.userId != _myUserId || id.deviceId != _myDeviceId,
  );

  void dispose() {
    unawaited(
      _end('a call that was let go').whenComplete(() {
        _phaseController.close();
        _remoteJoinedController.close();
      }),
    );
  }
}

class MicrophoneUnavailable implements Exception {
  const MicrophoneUnavailable();
}
