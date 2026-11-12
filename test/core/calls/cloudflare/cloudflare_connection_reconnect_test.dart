import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:zuno/core/calls/models/call_engine_status.dart';
import 'package:zuno/core/calls/models/call_kind.dart';

import '../../../helpers/call_fixtures.dart';
import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_webrtc.dart';
import 'cloudflare_engine_harness.dart';

void main() {
  void inCall(void Function(EngineHarness call) body) =>
      runEngineCall(body, kind: CallKind.voice);

  Iterable<SfuRequest> rejoinSessions(EngineHarness call) =>
      call.sfu.requests.where((r) => r.path == '/sessions/new').skip(1);

  List<CallEngineStatus> statusesFromNow(EngineHarness call) {
    final statuses = <CallEngineStatus>[];
    call.engine.statusStream.listen(statuses.add);
    return statuses;
  }

  group('ICE servers', () {
    test(
      'session creation never waits for the mint; the peer connection does',
      () {
        fakeAsync((async) {
          final backend = FakeWebRtcBackend();
          final servers = Completer<List<Map<String, Object?>>>();
          final sessions = <int>[];
          final (:engine, connection: _) = buildCloudflareEngine(
            iceServers: servers.future,
            webRtc: backend,
            placeholders: FakePlaceholderVideoSource(),
            httpClient: FakeHttpClient((request) async {
              sessions.add(sessions.length + 1);
              return http.Response(jsonEncode({'sessionId': 's1'}), 200);
            }),
          );
          Map<String, dynamic>? configuration() =>
              backend.peerConnections.firstOrNull?.configuration;

          unawaited(joinWithLocalMedia(engine).catchError((Object _) {}));
          async.elapse(const Duration(seconds: 5));

          expect(sessions, hasLength(1));
          expect(configuration(), isNull);

          const turn = [
            {
              'urls': 'turn:turn.example.org:3478',
              'username': 'u',
              'credential': 'c',
            },
          ];
          servers.complete(turn);
          async.flushMicrotasks();

          expect(configuration()?['iceServers'], turn);
          unawaited(engine.leave());
          async.flushMicrotasks();
        });
      },
    );
  });

  group('happy path', () {
    test(
      'a disconnect that recovers within the grace period never rejoins',
      () {
        inCall((call) {
          call.joinEncrypted();
          final statuses = statusesFromNow(call);

          call.pc.changeState(
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
          );
          call.async.elapse(const Duration(seconds: 3));
          call.pc.changeState(
            RTCPeerConnectionState.RTCPeerConnectionStateConnected,
          );
          call.async.elapse(const Duration(seconds: 10));
          call.flush();

          expect(rejoinSessions(call), isEmpty);
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
        inCall((call) {
          call.joinEncrypted();
          final statuses = statusesFromNow(call);
          final publishing = Completer<void>();
          call.backend.transceiverGate = publishing;

          call.pc.changeState(
            RTCPeerConnectionState.RTCPeerConnectionStateFailed,
          );
          call.async.elapse(const Duration(seconds: 2));
          call.flush();
          expect(call.backend.peerConnections, hasLength(2));
          call.pc.changeState(
            RTCPeerConnectionState.RTCPeerConnectionStateConnecting,
          );
          call.pc.changeState(RTCPeerConnectionState.RTCPeerConnectionStateNew);
          call.flush();

          expect(call.engine.status, CallEngineStatus.reconnecting);
          expect(statuses, isNot(contains(CallEngineStatus.connecting)));
          expect(statuses, isNot(contains(CallEngineStatus.connected)));
          publishing.complete();
        });
      },
    );

    test('a disconnect outlasting the grace period rejoins', () {
      inCall((call) {
        call.joinEncrypted();

        call.pc.changeState(
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
        );
        call.async.elapse(const Duration(seconds: 5));
        call.async.elapse(const Duration(seconds: 5));
        call.flush();

        expect(rejoinSessions(call), isNotEmpty);
        expect(
          call.engine.status,
          anyOf(CallEngineStatus.reconnecting, CallEngineStatus.failed),
        );
      });
    });

    test('three failed rejoins end in failed status', () {
      inCall((call) {
        call.joinEncrypted();
        call.sfu.sessionStatus = 500;

        call.pc.changeState(
          RTCPeerConnectionState.RTCPeerConnectionStateFailed,
        );
        call.async.elapse(const Duration(seconds: 30));
        call.flush();

        expect(rejoinSessions(call), hasLength(3));
        expect(call.engine.status, CallEngineStatus.failed);
      });
    });

    test('a gone session route ends the rejoin at once and is not '
        'reported', () {
      final lines = recordDebugPrints();
      inCall((call) {
        call.joinEncrypted();
        call.sfu
          ..sessionStatus = 404
          ..sessionRefusal = {
            'errcode': 'M_UNRECOGNIZED',
            'error': 'Unrecognized request',
          };

        call.pc.changeState(
          RTCPeerConnectionState.RTCPeerConnectionStateFailed,
        );
        call.async.elapse(const Duration(seconds: 30));
        call.flush();

        expect(call.engine.status, CallEngineStatus.failed);
        expect(rejoinSessions(call), hasLength(1));
        expect(lines.where((l) => l.startsWith('zuno/caught:')), isEmpty);
      });
    });

    test('a full call at the rejoin ends it at once', () {
      inCall((call) {
        call.joinEncrypted();
        call.sfu
          ..sessionStatus = 403
          ..sessionRefusal = {
            'errcode': 'IM.ZUNO.CALL_FULL',
            'error': 'This call is full',
            'max_participants': 8,
          };

        call.pc.changeState(
          RTCPeerConnectionState.RTCPeerConnectionStateFailed,
        );
        call.async.elapse(const Duration(seconds: 30));
        call.flush();

        expect(call.engine.status, CallEngineStatus.failed);
        expect(rejoinSessions(call), hasLength(1));
      });
    });

    test('a failure after leave is ignored', () {
      inCall((call) {
        call.joinEncrypted();
        final pc = call.pc;
        call.leave();

        pc.changeState(RTCPeerConnectionState.RTCPeerConnectionStateFailed);
        call.async.elapse(const Duration(seconds: 30));
        call.flush();

        expect(rejoinSessions(call), isEmpty);
        expect(call.engine.status, CallEngineStatus.disconnected);
      });
    });
  });
}
