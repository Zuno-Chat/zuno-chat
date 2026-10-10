import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/live_location_capture.dart';
import 'package:zuno/core/location/live_location_policy.dart';
import 'package:zuno/core/location/live_location_protocol.dart';

import '../../helpers/native_method_calls.dart';
import '../../helpers/platform_capabilities.dart';

const _methods = MethodChannel('zuno/live_location');
const _fixes = EventChannel('zuno/live_location/fixes');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final notice = LiveLocationNotice(
    title: 'Sharing live location',
    text: 'With Alex',
    endsAt: DateTime.fromMillisecondsSinceEpoch(1700003600000),
    roomId: '!r:x',
  );

  late List<MethodCall> calls;
  late ChannelLiveLocationCapture capture;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(_methods, (call) async {
      calls.add(call);
      return null;
    });
    capture = ChannelLiveLocationCapture(capabilities: androidCapabilities);
  });

  tearDown(() {
    capture.dispose();
    messenger.setMockMethodCallHandler(_methods, null);
    messenger.setMockStreamHandler(_fixes, null);
  });

  void streamFixes(List<Object?> events) => messenger.setMockStreamHandler(
    _fixes,
    MockStreamHandler.inline(
      onListen: (_, sink) {
        for (final event in events) {
          sink.success(event);
        }
      },
    ),
  );

  test('start hands native code the mode and the notice', () async {
    await capture.start(LiveLocationMode.coarse, notice);

    expect(calls.single.method, 'start');
    expect(calls.single.arguments, {
      'mode': 'coarse',
      'notice': {
        'title': 'Sharing live location',
        'text': 'With Alex',
        'endsAtMs': 1700003600000,
        'roomId': '!r:x',
      },
    });
  });

  test('mode, notice, wake lock and stop calls reach native code', () async {
    await capture.setMode(LiveLocationMode.precise);
    await capture.updateNotice(notice);
    await capture.releaseWakeLock(7);
    await capture.stop();

    expect(calls.map((c) => c.method), [
      'setMode',
      'updateNotice',
      'releaseWakeLock',
      'stop',
    ]);
    expect(calls[0].arguments, {'mode': 'precise'});
    expect(calls[2].arguments, {'seq': 7});
  });

  test('a native fix becomes a position with its sequence number', () async {
    streamFixes([
      {
        'lat': 52.5,
        'lon': 13.4,
        'accuracy': 12.0,
        'ts': 1700000000000,
        'seq': 3,
      },
    ]);

    final event = await capture.events.first;

    expect(event, isA<LiveCaptureFix>());
    final fix = (event as LiveCaptureFix).fix;
    expect(fix.seq, 3);
    expect(
      fix.position,
      LivePosition(
        geo: const GeoUri(
          latitude: 52.5,
          longitude: 13.4,
          uncertaintyMeters: 12,
        ),
        at: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      ),
    );
  });

  test('a fix without accuracy carries no uncertainty', () async {
    streamFixes([
      {'lat': 1.0, 'lon': 2.0, 'ts': 1700000000000, 'seq': 1},
    ]);

    final event = await capture.events.first as LiveCaptureFix;

    expect(event.fix.position.geo.uncertaintyMeters, isNull);
  });

  test('native errors become a lost capture with their reason', () async {
    streamFixes([
      {'error': 'services_off'},
      {'error': 'denied'},
      {'error': 'something else'},
    ]);

    final events = await capture.events.take(3).toList();

    expect(events.cast<LiveCaptureLost>().map((e) => e.reason), [
      LiveCaptureFailure.servicesOff,
      LiveCaptureFailure.denied,
      LiveCaptureFailure.failed,
    ]);
  });

  test('a native stream error ends capture as failed', () async {
    messenger.setMockStreamHandler(
      _fixes,
      MockStreamHandler.inline(onListen: (_, sink) => sink.error(code: 'boom')),
    );

    final event = await capture.events.first;

    expect((event as LiveCaptureLost).reason, LiveCaptureFailure.failed);
  });

  test('a fix that is not a real place is ignored', () async {
    streamFixes([
      {'lat': 95.0, 'lon': 13.4, 'ts': 1700000000000, 'seq': 1},
      {'lat': 'x', 'lon': 13.4, 'ts': 1700000000000, 'seq': 2},
      {'lat': 1.0, 'lon': 2.0, 'ts': 1700000000000, 'seq': 3},
    ]);

    final event = await capture.events.first as LiveCaptureFix;

    expect(event.fix.seq, 3);
  });

  test('the notification Stop reaches Dart as a stop request', () async {
    final requested = capture.stopRequests.first;

    await callFromNative(_methods, 'stopRequested');

    await expectLater(requested, completes);
  });

  test('without the capability nothing reaches native code', () async {
    final off = ChannelLiveLocationCapture(
      capabilities: capabilitiesLike(androidCapabilities, liveLocation: false),
    );

    await expectLater(
      off.start(LiveLocationMode.coarse, notice),
      throwsA(isA<LiveCaptureUnavailable>()),
    );
    await off.setMode(LiveLocationMode.precise);
    await off.stop();
    expect(calls, isEmpty);
    expect(await off.events.isEmpty, true);
    off.dispose();
  });

  test('a missing native handler means capture is unavailable', () async {
    messenger.setMockMethodCallHandler(_methods, null);

    await expectLater(
      capture.start(LiveLocationMode.coarse, notice),
      throwsA(isA<LiveCaptureUnavailable>()),
    );
    await capture.stop();
  });

  test('a native start failure means capture is unavailable', () async {
    messenger.setMockMethodCallHandler(_methods, (call) async {
      throw PlatformException(code: 'start_failed');
    });

    await expectLater(
      capture.start(LiveLocationMode.coarse, notice),
      throwsA(isA<LiveCaptureUnavailable>()),
    );
  });
}
