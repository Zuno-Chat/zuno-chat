import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAudioPlatform {
  final calls = <MethodCall>[];
  final _sinks = <String, MockStreamHandlerEventSink>{};
  int positionMs = 0;

  Iterable<String> get methods => calls.map((call) => call.method);

  Iterable<MethodCall> named(String method) =>
      calls.where((call) => call.method == method);

  void _emit(Map<String, Object?> event) {
    for (final sink in _sinks.values) {
      sink.success(event);
    }
  }

  void finishPlaying() => _emit({'event': 'audio.onComplete'});

  void reportDuration(int ms) =>
      _emit({'event': 'audio.onDuration', 'value': ms});
}

Future<FakeAudioPlatform> installFakeAudioPlatform() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = FakeAudioPlatform();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const player = MethodChannel('xyz.luan/audioplayers');
  const global = MethodChannel('xyz.luan/audioplayers.global');
  const globalEvents = EventChannel('xyz.luan/audioplayers.global/events');
  final eventChannels = <EventChannel>[];

  messenger.setMockMethodCallHandler(global, (_) async => null);
  messenger.setMockStreamHandler(
    globalEvents,
    MockStreamHandler.inline(onListen: (_, _) {}),
  );
  messenger.setMockMethodCallHandler(player, (call) async {
    fake.calls.add(call);
    final playerId = (call.arguments as Map)['playerId'] as String;
    switch (call.method) {
      case 'create':
        final events = EventChannel('xyz.luan/audioplayers/events/$playerId');
        eventChannels.add(events);
        messenger.setMockStreamHandler(
          events,
          MockStreamHandler.inline(
            onListen: (_, sink) {
              fake._sinks[playerId] = sink;
            },
          ),
        );
      case 'setSourceBytes':
        fake._sinks[playerId]?.success({
          'event': 'audio.onPrepared',
          'value': true,
        });
      case 'seek':
        fake._sinks[playerId]?.success({'event': 'audio.onSeekComplete'});
      case 'getCurrentPosition':
        return fake.positionMs;
    }
    return null;
  });
  await AudioPlayer.global.ensureInitialized();
  addTearDown(() {
    messenger.setMockMethodCallHandler(player, null);
    messenger.setMockMethodCallHandler(global, null);
    messenger.setMockStreamHandler(globalEvents, null);
    for (final events in eventChannels) {
      messenger.setMockStreamHandler(events, null);
    }
  });
  return fake;
}
