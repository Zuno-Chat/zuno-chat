import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:matrix/matrix.dart' hide CallSession;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/models/call_engine_participant.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/calls/presentation/call_page.dart';

import '../../../helpers/fake_call_engine.dart';
import '../../../helpers/fake_matrix.dart';

class FakeCallSession implements CallSession {
  FakeCallSession({
    required this.room,
    required this.kind,
    this.role = CallSessionRole.callee,
    this._phase = CallSessionPhase.connecting,
  }) : engine = FakeCallEngine(kind: kind);

  @override
  final Room room;
  @override
  CallKind kind;
  @override
  final CallSessionRole role;
  @override
  final FakeCallEngine engine;
  @override
  String get callId => 'call-1';

  CallSessionPhase _phase;
  final _phases = StreamController<CallSessionPhase>.broadcast();
  final _remoteJoined = StreamController<void>.broadcast();

  @override
  CallSessionPhase get phase => _phase;
  @override
  Stream<CallSessionPhase> get phaseStream => _phases.stream;
  @override
  Stream<void> get remoteJoinedStream => _remoteJoined.stream;

  @override
  bool everHadRemote = false;
  @override
  CallEndReason? endReason;
  @override
  String? failedMessage;

  bool microphoneGranted = true;
  int membershipRefreshes = 0;
  int hangUps = 0;

  @override
  Future<void> ensurePermissions() async {
    if (!microphoneGranted) throw StateError('Microphone permission denied');
  }

  @override
  Future<void> refreshMembership() async => membershipRefreshes++;

  @override
  Future<void> hangUp() async => hangUps++;

  void moveTo(CallSessionPhase next) {
    _phase = next;
    _phases.add(next);
  }

  void remoteJoins() {
    everHadRemote = true;
    _remoteJoined.add(null);
  }

  void end({CallEndReason reason = CallEndReason.hungUp, String? message}) {
    endReason = reason;
    failedMessage = message;
    moveTo(CallSessionPhase.ended);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMediaStream extends MediaStream {
  FakeMediaStream(String id) : super(id, 'local');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CallEngineParticipant localParticipant({
  bool muted = false,
  bool camera = false,
}) => CallEngineParticipant(
  id: const VoipParticipantId(userId: 'local', deviceId: 'local'),
  isLocal: true,
  audioMuted: muted,
  videoEnabled: camera,
  videoStream: camera ? FakeMediaStream('local-video') : null,
  encrypted: true,
);

CallEngineParticipant remoteParticipant({
  String userId = '@ann:example.org',
  bool camera = false,
}) => CallEngineParticipant(
  id: VoipParticipantId(userId: userId, deviceId: 'ANN'),
  isLocal: false,
  videoEnabled: camera,
  videoStream: camera ? FakeMediaStream('$userId-video') : null,
  encrypted: true,
);

class CallPageHarness {
  CallPageHarness(this.tester, {PlatformCapabilities? capabilities}) {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    void mock(String name, Future<Object?>? Function(MethodCall call) handle) {
      final channel = MethodChannel(name);
      messenger.setMockMethodCallHandler(channel, handle);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }

    mock('zuno/calls', (call) async {
      calls.add(call);
      return null;
    });
    mock('FlutterWebRTC.Method', (call) async {
      webrtc.add(call);
      return switch (call.method) {
        'getSources' => {
          'sources': [
            for (final id in audioOutputs)
              {
                'deviceId': id,
                'groupId': id,
                'kind': 'audiooutput',
                'label': id,
              },
          ],
        },
        'createVideoRenderer' => {'textureId': _textureFor()},
        _ => null,
      };
    });
    for (final name in [
      'FlutterWebRTC.Event',
      'zuno/vibration',
      'dexterous.com/flutter/local_notifications',
    ]) {
      mock(name, (_) async => null);
    }

    const wakelock =
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
    messenger.setMockMessageHandler(wakelock, (message) async {
      final args = const _PigeonReader().decodeMessage(message) as List;
      wakelockToggles.add((args.single as List).single as bool);
      return const StandardMessageCodec().encodeMessage(<Object?>[null]);
    });
    addTearDown(() => messenger.setMockMessageHandler(wakelock, null));

    container = ProviderContainer(
      overrides: [
        if (capabilities != null)
          platformCapabilitiesProvider.overrideWithValue(capabilities),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(
      () => CallNotificationService.instance.inPictureInPicture.value = false,
    );
  }

  final WidgetTester tester;
  late final ProviderContainer container;
  final navigatorKey = GlobalKey<NavigatorState>();

  final calls = <MethodCall>[];
  final webrtc = <MethodCall>[];
  final wakelockToggles = <bool>[];
  List<String> audioOutputs = ['earpiece', 'speaker'];
  var _nextTexture = 0;

  int _textureFor() {
    final id = ++_nextTexture;
    final channel = MethodChannel('FlutterWebRTC/Texture$id');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    return id;
  }

  static Room buildRoom() {
    final room = buildTestRoom(buildTestClient(userId: '@me:example.org'));
    room.setState(
      StrippedStateEvent(
        type: EventTypes.RoomName,
        senderId: '@me:example.org',
        stateKey: '',
        content: {'name': 'Weekend hike'},
      ),
    );
    for (final (userId, name) in [
      ('@me:example.org', 'Me'),
      ('@ann:example.org', 'Ann'),
    ]) {
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomMember,
          senderId: userId,
          stateKey: userId,
          content: {'membership': 'join', 'displayname': name},
        ),
      );
    }
    return room;
  }

  Future<void> open(FakeCallSession session) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);
    container.read(activeCallProvider.notifier).set(session);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: zunoLightTheme,
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('Chat')),
        ),
      ),
    );
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => CallPage(session: session)),
      ),
    );
    await settle();
  }

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> changeAudioOutputs(List<String> ids) async {
    audioOutputs = ids;
    navigator.mediaDevices.ondevicechange?.call(null);
    await settle();
  }

  List<Object?> argsOf(String method) => [
    for (final call in calls)
      if (call.method == method) call.arguments,
  ];

  int count(String method) => argsOf(method).length;

  bool get ringbackPlaying =>
      calls
          .where(
            (c) =>
                c.method == 'startRingbackTone' ||
                c.method == 'stopRingbackTone',
          )
          .lastOrNull
          ?.method ==
      'startRingbackTone';

  bool? get proximityScreenOff =>
      (argsOf('setProximityScreenOff').lastOrNull as Map?)?['enabled'] as bool?;

  bool? get showOverLockscreen =>
      (argsOf('setShowOverLockscreen').lastOrNull as Map?)?['show'] as bool?;

  bool? get pictureInPictureEligible =>
      (argsOf('setPictureInPicture').lastOrNull as Map?)?['eligible'] as bool?;

  String? get audioRoute {
    for (final call in webrtc.reversed) {
      final args = call.arguments as Map?;
      if (call.method == 'enableSpeakerphone') {
        return args!['enable'] == true ? 'speaker' : 'earpiece';
      }
      if (call.method == 'selectAudioOutput') {
        return args!['deviceId'] as String;
      }
    }
    return null;
  }

  int get audioRouteChanges => webrtc
      .where(
        (c) =>
            c.method == 'enableSpeakerphone' || c.method == 'selectAudioOutput',
      )
      .length;

  Finder get speakerButton => find.byWidgetPredicate(
    (w) =>
        w is Tooltip &&
        (w.message == 'Turn speaker on' || w.message == 'Turn speaker off'),
  );

  IconData? get speakerIcon => tester
      .widget<Icon>(
        find.descendant(of: speakerButton, matching: find.byType(Icon)),
      )
      .icon;
}

class _PigeonReader extends StandardMessageCodec {
  const _PigeonReader();

  @override
  Object? readValueOfType(int type, ReadBuffer buffer) =>
      type == 129 ? readValue(buffer) : super.readValueOfType(type, buffer);
}
