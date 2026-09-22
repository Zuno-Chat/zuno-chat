import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/calls/cloudflare/cloudflare_call_engine.dart';
import 'package:zuno/core/calls/models/call_engine_status.dart';
import 'package:zuno/core/calls/models/call_kind.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const webrtcChannel = MethodChannel('FlutterWebRTC.Method');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(webrtcChannel, (call) async {
      throw PlatformException(
        code: 'test',
        message: 'no native WebRTC in tests',
      );
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(webrtcChannel, null);
  });

  ({CloudflareCallEngine engine, List<int> sessions}) build() {
    final sessions = <int>[];
    final engine = CloudflareCallEngine(
      gatewayBaseUri: Uri.parse('https://example.org/calls'),
      gatewayAuthorizationProvider: ({bool refresh = false}) async =>
          'Bearer test-token',
      kind: CallKind.voice,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/sessions/new')) {
          sessions.add(sessions.length + 1);
          return http.Response(
            jsonEncode({'sessionId': 's${sessions.length}'}),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );
    return (engine: engine, sessions: sessions);
  }

  group('happy path', () {
    test(
      'a disconnect that recovers within the grace period never rejoins',
      () {
        fakeAsync((async) {
          final (:engine, :sessions) = build();
          final statuses = <CallEngineStatus>[];
          engine.statusStream.listen(statuses.add);

          engine.handleConnectionStateForTest(
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
          );
          async.elapse(const Duration(seconds: 3));
          engine.handleConnectionStateForTest(
            RTCPeerConnectionState.RTCPeerConnectionStateConnected,
          );
          async.elapse(const Duration(seconds: 10));

          expect(sessions, isEmpty);
          expect(statuses, [
            CallEngineStatus.reconnecting,
            CallEngineStatus.connected,
          ]);
        });
      },
    );
  });

  group('sad paths', () {
    test(
      'a rejoin in flight keeps reporting reconnecting, never connecting',
      () {
        fakeAsync((async) {
          final (:engine, sessions: _) = build();
          final statuses = <CallEngineStatus>[];
          engine.statusStream.listen(statuses.add);

          engine.handleConnectionStateForTest(
            RTCPeerConnectionState.RTCPeerConnectionStateFailed,
          );
          async.flushMicrotasks();
          engine.handleConnectionStateForTest(
            RTCPeerConnectionState.RTCPeerConnectionStateConnecting,
          );
          engine.handleConnectionStateForTest(
            RTCPeerConnectionState.RTCPeerConnectionStateNew,
          );
          async.flushMicrotasks();

          expect(engine.status, CallEngineStatus.reconnecting);
          expect(statuses, isNot(contains(CallEngineStatus.connecting)));
          expect(statuses, isNot(contains(CallEngineStatus.connected)));
        });
      },
    );

    test('a disconnect outlasting the grace period rejoins', () {
      fakeAsync((async) {
        final (:engine, :sessions) = build();
        engine.handleConnectionStateForTest(
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
        );
        async.elapse(const Duration(seconds: 5));
        async.elapse(const Duration(seconds: 5));

        expect(sessions, isNotEmpty);
        expect(
          engine.status,
          anyOf(CallEngineStatus.reconnecting, CallEngineStatus.failed),
        );
      });
    });

    test('three failed rejoins end in failed status', () {
      fakeAsync((async) {
        final (:engine, :sessions) = build();
        engine.handleConnectionStateForTest(
          RTCPeerConnectionState.RTCPeerConnectionStateFailed,
        );
        async.elapse(const Duration(seconds: 30));

        expect(sessions, hasLength(3));
        expect(engine.status, CallEngineStatus.failed);
      });
    });

    test('a failure after leave is ignored', () {
      fakeAsync((async) {
        final (:engine, :sessions) = build();
        engine.leave();
        async.flushMicrotasks();
        engine.handleConnectionStateForTest(
          RTCPeerConnectionState.RTCPeerConnectionStateFailed,
        );
        async.elapse(const Duration(seconds: 30));

        expect(sessions, isEmpty);
        expect(engine.status, CallEngineStatus.disconnected);
      });
    });
  });
}
