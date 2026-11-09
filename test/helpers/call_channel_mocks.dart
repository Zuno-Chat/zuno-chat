import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';

import 'fake_calls_channel.dart';
import 'fake_screen_awake.dart';
import 'native_method_calls.dart';

class CallChannelMocks {
  CallChannelMocks() {
    _native = installFakeCallsChannel(
      reply: (call) async {
        if (call.method == 'takeCallEvents') return _takeNativeEvents();
        return await callsReply?.call(call) ?? _nativeCallAudio(call);
      },
    );
    webrtc = recordMethodChannel(
      'FlutterWebRTC.Method',
      reply: (call) => switch (call.method) {
        'createVideoRenderer' => _createRenderer(),
        _ => null,
      },
    ).calls;
    silenceMethodChannels(const ['FlutterWebRTC.Event']);
  }

  late final RecordedMethodCalls _native;
  late final List<MethodCall> webrtc;
  final _screen = installFakeScreenAwake();
  final nativeEvents = <Map<String, Object?>>[];
  FutureOr<Object?> Function(MethodCall call)? callsReply;

  List<bool> get wakelockToggles => _screen.toggles;

  set wakelockFails(bool refuses) => _screen.refuses = refuses;
  int rendererCreatesToRefuse = 0;
  List<String> headsets = [];
  String? _callAudioRoute;
  List<String> _reportedHeadsets = const [];
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
    silenceMethodChannels(['FlutterWebRTC/Texture$id']);
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

  Map<String, Object?> get _callAudioState => {
    'route': ?_callAudioRoute,
    'headsets': headsets,
  };

  Object? _nativeCallAudio(MethodCall call) {
    final route = (call.arguments as Map?)?['route'] as String?;
    switch (call.method) {
      case 'startCallAudio':
        _callAudioRoute = route;
        _reportedHeadsets = [...headsets];
        return _callAudioState;
      case 'setAudioRoute':
        if (_callAudioRoute != null) _callAudioRoute = route;
      case 'stopCallAudio':
        _callAudioRoute = null;
      case 'audioRoute':
        return _callAudioState;
    }
    return null;
  }

  Iterable<MethodCall> get _routeRequests => calls.where(
    (c) => c.method == 'startCallAudio' || c.method == 'setAudioRoute',
  );

  String? get audioRoute =>
      (_routeRequests.lastOrNull?.arguments as Map?)?['route'] as String?;

  int get audioRouteChanges => _routeRequests.length;

  bool get callAudioRunning => _callAudioRoute != null;

  Future<void> reportHeadsets(List<String> connected) async {
    headsets = connected;
    if (!callAudioRunning || listEquals(_reportedHeadsets, connected)) return;
    _reportedHeadsets = [...connected];
    nativeEvents.add({
      'method': 'audioRouteChanged',
      'arguments': _callAudioState,
    });
    await CallNotificationService.instance.takeQueuedNativeCalls();
  }
}
