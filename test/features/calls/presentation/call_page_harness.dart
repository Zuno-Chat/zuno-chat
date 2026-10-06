import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:matrix/matrix.dart' hide CallSession;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/calls/presentation/call_page.dart';

import '../../../helpers/fake_call_session.dart';

export '../../../helpers/fake_call_session.dart';

class CallPageHarness {
  CallPageHarness(
    this.tester, {
    PlatformCapabilities? capabilities,
    List<Override> overrides = const [],
  }) {
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
      await wakelockGate?.future;
      return const StandardMessageCodec().encodeMessage(<Object?>[null]);
    });
    addTearDown(() => messenger.setMockMessageHandler(wakelock, null));

    container = ProviderContainer(
      overrides: [
        if (capabilities != null)
          platformCapabilitiesProvider.overrideWithValue(capabilities),
        ...overrides,
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
  Completer<void>? wakelockGate;
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

  static Room buildRoom() => buildCallRoom();

  Future<void> open(FakeCallSession session) async {
    await showChat();
    pushCall(session);
    await settle();
  }

  Future<void> showChat() async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);
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
  }

  void pushCall(FakeCallSession session) {
    container.read(activeCallProvider.notifier).set(session);
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => CallPage(session: session)),
      ),
    );
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
    await tester.pump(const Duration(seconds: 1));
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

  ({String? streamId, String? ownerTag})? get pictureInPictureVideo {
    final args = argsOf('setPictureInPicture').lastOrNull as Map?;
    if (args == null) return null;
    return (
      streamId: args['streamId'] as String?,
      ownerTag: args['ownerTag'] as String?,
    );
  }

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
