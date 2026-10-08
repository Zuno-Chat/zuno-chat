import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_calls_channel.dart';

const _wakelockChannel =
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';

class CallChannelMocks {
  CallChannelMocks() {
    _native = installFakeCallsChannel(
      reply: (call) => call.method == 'takeCallEvents'
          ? _takeNativeEvents()
          : callsReply?.call(call),
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    void mock(String name, Future<Object?>? Function(MethodCall call) handle) {
      final channel = MethodChannel(name);
      messenger.setMockMethodCallHandler(channel, handle);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }

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
        'createVideoRenderer' => _createRenderer(),
        _ => null,
      };
    });
    mock('FlutterWebRTC.Event', (_) async => null);

    messenger.setMockMessageHandler(_wakelockChannel, (message) async {
      final args = const _PigeonReader().decodeMessage(message) as List;
      wakelockToggles.add((args.single as List).single as bool);
      await wakelockGate?.future;
      return const StandardMessageCodec().encodeMessage(
        wakelockFails
            ? <Object?>['wakelock-refused', null, null]
            : <Object?>[null],
      );
    });
    addTearDown(() => messenger.setMockMessageHandler(_wakelockChannel, null));
  }

  late final RecordedCallsChannel _native;
  final webrtc = <MethodCall>[];
  final wakelockToggles = <bool>[];
  final nativeEvents = <Map<String, Object?>>[];
  FutureOr<Object?> Function(MethodCall call)? callsReply;
  Completer<void>? wakelockGate;
  bool wakelockFails = false;
  int rendererCreatesToRefuse = 0;
  List<String> audioOutputs = ['earpiece', 'speaker'];
  var _nextTexture = 0;

  List<MethodCall> get calls => _native.calls;

  Map<String, Object?> _createRenderer() {
    if (rendererCreatesToRefuse > 0) {
      rendererCreatesToRefuse--;
      throw PlatformException(code: 'renderer-refused');
    }
    return {'textureId': _textureFor()};
  }

  int _textureFor() {
    final id = ++_nextTexture;
    final channel = MethodChannel('FlutterWebRTC/Texture$id');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    return id;
  }

  List<Map<String, Object?>> _takeNativeEvents() {
    final taken = [...nativeEvents];
    nativeEvents.clear();
    return taken;
  }

  List<Object?> argsOf(String method) => _native.argsOf(method);

  int count(String method) => _native.count(method);

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
}

class _PigeonReader extends StandardMessageCodec {
  const _PigeonReader();

  @override
  Object? readValueOfType(int type, ReadBuffer buffer) =>
      type == 129 ? readValue(buffer) : super.readValueOfType(type, buffer);
}
