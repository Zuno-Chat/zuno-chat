import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/best_effort.dart';
import '../platform/platform_capabilities.dart';
import 'geo_uri.dart';
import 'live_location_policy.dart';
import 'live_location_protocol.dart';

const _methods = MethodChannel('zuno/live_location');
const _fixes = EventChannel('zuno/live_location/fixes');

@immutable
class LiveFix {
  final LivePosition position;
  final int seq;

  const LiveFix({required this.position, required this.seq});
}

enum LiveCaptureFailure { servicesOff, denied, ended, failed }

sealed class LiveCaptureEvent {
  const LiveCaptureEvent();
}

final class LiveCaptureFix extends LiveCaptureEvent {
  final LiveFix fix;

  const LiveCaptureFix(this.fix);
}

final class LiveCaptureLost extends LiveCaptureEvent {
  final LiveCaptureFailure reason;

  const LiveCaptureLost(this.reason);
}

@immutable
class LiveLocationNotice {
  final String title;
  final String text;
  final DateTime endsAt;
  final String? roomId;

  const LiveLocationNotice({
    required this.title,
    required this.text,
    required this.endsAt,
    this.roomId,
  });

  Map<String, Object?> toArguments() => {
    'title': title,
    'text': text,
    'endsAtMs': endsAt.millisecondsSinceEpoch,
    'roomId': roomId,
  };

  @override
  bool operator ==(Object other) =>
      other is LiveLocationNotice &&
      other.title == title &&
      other.text == text &&
      other.endsAt == endsAt &&
      other.roomId == roomId;

  @override
  int get hashCode => Object.hash(title, text, endsAt, roomId);
}

class LiveCaptureUnavailable implements Exception {
  const LiveCaptureUnavailable();
}

abstract interface class LiveLocationCapture {
  Stream<LiveCaptureEvent> get events;

  Stream<void> get stopRequests;

  Future<void> start(LiveLocationMode mode, LiveLocationNotice notice);

  Future<void> setMode(LiveLocationMode mode);

  Future<void> updateNotice(LiveLocationNotice notice);

  Future<void> releaseWakeLock(int seq);

  Future<void> stop();
}

class ChannelLiveLocationCapture implements LiveLocationCapture {
  ChannelLiveLocationCapture({required PlatformCapabilities capabilities})
    : _enabled = capabilities.liveLocation {
    if (_enabled) _methods.setMethodCallHandler(_onNativeCall);
  }

  final bool _enabled;
  final _stopRequests = StreamController<void>.broadcast();

  @override
  late final Stream<LiveCaptureEvent> events = _enabled
      ? _fixes.receiveBroadcastStream().transform(_captureEvents)
      : const Stream.empty();

  @override
  Stream<void> get stopRequests => _stopRequests.stream;

  @override
  Future<void> start(LiveLocationMode mode, LiveLocationNotice notice) async {
    if (!_enabled) throw const LiveCaptureUnavailable();
    try {
      await _methods.invokeMethod('start', {
        'mode': mode.name,
        'notice': notice.toArguments(),
      });
    } on MissingPluginException {
      throw const LiveCaptureUnavailable();
    } on PlatformException catch (error) {
      logCaught('live location start', error.code);
      throw const LiveCaptureUnavailable();
    }
  }

  @override
  Future<void> setMode(LiveLocationMode mode) =>
      _call('setMode', {'mode': mode.name});

  @override
  Future<void> updateNotice(LiveLocationNotice notice) =>
      _call('updateNotice', notice.toArguments());

  @override
  Future<void> releaseWakeLock(int seq) =>
      _call('releaseWakeLock', {'seq': seq});

  @override
  Future<void> stop() => _call('stop', null);

  void dispose() {
    if (_enabled) _methods.setMethodCallHandler(null);
    unawaited(_stopRequests.close());
  }

  Future<void> _call(String method, Map<String, Object?>? arguments) async {
    if (!_enabled) return;
    await runBestEffort(
      () => _methods.invokeMethod(method, arguments),
      label: 'live location $method',
    );
  }

  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method == 'stopRequested') _stopRequests.add(null);
  }
}

final _captureEvents =
    StreamTransformer<Object?, LiveCaptureEvent>.fromHandlers(
      handleData: (raw, sink) {
        if (_eventFrom(raw) case final event?) sink.add(event);
      },
      handleError: (_, _, sink) =>
          sink.add(const LiveCaptureLost(LiveCaptureFailure.failed)),
    );

LiveCaptureEvent? _eventFrom(Object? raw) {
  if (raw is! Map) return null;
  final error = raw['error'];
  if (error != null) {
    return LiveCaptureLost(switch (error) {
      'services_off' => LiveCaptureFailure.servicesOff,
      'denied' => LiveCaptureFailure.denied,
      'ended' => LiveCaptureFailure.ended,
      _ => LiveCaptureFailure.failed,
    });
  }
  final lat = raw['lat'];
  final lon = raw['lon'];
  final at = liveTimestamp(raw['ts']);
  final seq = raw['seq'];
  if (lat is! double || lon is! double || at == null || seq is! int) {
    return null;
  }
  if (!lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) {
    return null;
  }
  final accuracy = raw['accuracy'];
  return LiveCaptureFix(
    LiveFix(
      position: LivePosition(
        geo: GeoUri(
          latitude: lat,
          longitude: lon,
          uncertaintyMeters:
              accuracy is double && accuracy.isFinite && accuracy > 0
              ? accuracy
              : null,
        ),
        at: at,
      ),
      seq: seq,
    ),
  );
}

final liveLocationCaptureProvider = Provider<LiveLocationCapture>((ref) {
  final capture = ChannelLiveLocationCapture(
    capabilities: ref.watch(platformCapabilitiesProvider),
  );
  ref.onDispose(capture.dispose);
  return capture;
});
