import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/platform_capabilities.dart';
import 'cloudflare_engine_harness.dart';

void main() {
  void inCall(
    void Function(EngineHarness call) body, {
    CallKind kind = CallKind.video,
    PlatformCapabilities? capabilities,
  }) => runEngineCall(
    body,
    kind: kind,
    capabilities: capabilities ?? androidCapabilities,
  );

  void connectionFails(EngineHarness call) {
    call.engine.handleConnectionStateForTest(
      RTCPeerConnectionState.RTCPeerConnectionStateFailed,
    );
    call.async.elapse(const Duration(seconds: 2));
    call.flush();
  }

  List<String> journalOf(EngineHarness call, void Function() action) {
    final from = call.backend.journal.length;
    action();
    return call.backend.journal.sublist(from);
  }

  bool removesEncryption(String entry) =>
      entry.endsWith('cryptor disposed') || entry == 'key provider disposed';

  List<RTCRtpSender?> encryptedSenders(EngineHarness call, String label) => [
    for (final cryptor in call.backend.cryptors.live)
      if (cryptor.participantId == label) cryptor.sender,
  ];

  ({MediaStreamTrack? track, bool enabled}) placedOff(MediaStreamTrack track) =>
      (track: track, enabled: false);

  group('hanging up', () {
    test('switches the microphone and camera off and closes the connection '
        'before removing any encryption', () {
      inCall((call) {
        call.joinEncrypted();
        final microphone = call.microphone.id;
        final camera = call.camera.id;

        final leaving = journalOf(call, call.leave);

        final closed = leaving.indexOf('pc1 disposed');
        expect(closed, isNonNegative);
        expect(
          leaving.take(closed),
          containsAll(['$microphone off', '$camera off']),
        );
        expect(leaving.take(closed).where(removesEncryption), isEmpty);
        expect(
          leaving.skip(closed),
          containsAll([
            'local-audio cryptor disposed',
            'local-video cryptor disposed',
            'key provider disposed',
          ]),
        );
      });
    });
  });

  group('a rejoin', () {
    test('switches the microphone off and closes the old connection before '
        'removing its encryption, then encrypts the new one', () {
      inCall((call) {
        call.joinEncrypted();
        final microphone = call.microphone.id;

        final rejoining = journalOf(call, () => connectionFails(call));

        final closed = rejoining.indexOf('pc1 disposed');
        expect(closed, isNonNegative);
        expect(rejoining.take(closed), contains('$microphone off'));
        expect(rejoining.take(closed).where(removesEncryption), isEmpty);
        expect(
          rejoining.skip(closed),
          containsAll([
            'local-audio cryptor disposed',
            'local-video cryptor disposed',
          ]),
        );
        final [audio, video] = call.pc.rtpTransceivers;
        expect(encryptedSenders(call, 'local-audio'), [same(audio.sender)]);
        expect(encryptedSenders(call, 'local-video'), [same(video.sender)]);
        expect(call.microphone.enabled, isTrue);
      });
    });

    test('a first key that arrives while the new connection opens encrypts '
        'the new connection, and the call goes on', () {
      inCall((call) {
        call.join();
        final gate = Completer<void>();
        call.sfu.sessionGate = gate;
        connectionFails(call);

        call.encrypt();
        gate.complete();
        call.flush();

        expect(call.backend.peerConnections, hasLength(2));
        final [audio, video] = call.pc.rtpTransceivers;
        expect(encryptedSenders(call, 'local-audio'), [same(audio.sender)]);
        expect(encryptedSenders(call, 'local-video'), [same(video.sender)]);
        expect(call.microphone.enabled, isTrue);
        expect(call.camera.enabled, isTrue);
      });
    });

    test('a first key that arrives once the new connection is open, before '
        'anything is on it, encrypts what is then put on it', () {
      inCall((call) {
        call.join();
        call.wait(call.engine.setCameraEnabled(false));
        final cameraGate = Completer<void>();
        call.backend.captureGate = cameraGate;
        final turningOn = call.engine.setCameraEnabled(true);
        call.flush();
        connectionFails(call);

        call.encrypt();
        cameraGate.complete();
        call.flush();
        call.wait(turningOn);

        expect(call.backend.peerConnections, hasLength(2));
        final [audio, video] = call.pc.rtpTransceivers;
        expect(encryptedSenders(call, 'local-audio'), [same(audio.sender)]);
        expect(encryptedSenders(call, 'local-video'), [same(video.sender)]);
        expect(call.microphone.enabled, isTrue);
      });
    });

    test('encryption still being set up for the old connection is never '
        'used on the new one', () {
      inCall((call) {
        call.join();
        final gate = Completer<void>();
        call.backend.cryptors.senderGate = gate;
        final encrypting = call.engine.setEncryptionKey(callKey());
        call.flush();

        connectionFails(call);
        gate.complete();
        call.flush();
        call.wait(encrypting);

        expect(call.backend.peerConnections, hasLength(2));
        final [audio, video] = call.pc.rtpTransceivers;
        expect(encryptedSenders(call, 'local-audio'), [same(audio.sender)]);
        expect(encryptedSenders(call, 'local-video'), [same(video.sender)]);
        expect(call.microphone.enabled, isTrue);
      });
    });
  });

  group('without a call key', () {
    test('the microphone and camera land on their senders switched off', () {
      inCall((call) {
        call.join();

        final [audio, video] = call.pc.rtpTransceivers;
        expect(audio.sender.placements, [placedOff(call.microphone)]);
        expect(video.sender.placements, [placedOff(call.camera)]);
      });
    });

    test('a camera turned back on lands on its sender switched off', () {
      inCall((call) {
        call.join();
        call.wait(call.engine.setCameraEnabled(false));

        call.wait(call.engine.setCameraEnabled(true));

        expect(call.videoSlot.sender.placements.last, placedOff(call.camera));
      });
    });

    test('a camera that comes back with the app lands on its sender '
        'switched off', () {
      inCall((call) {
        call.join();
        call.wait(call.engine.setAppInBackground(true));

        call.wait(call.engine.setAppInBackground(false));

        expect(call.videoSlot.sender.placements.last, placedOff(call.camera));
      }, capabilities: androidCapabilities);
    });

    test('a voice call switched to video sends its camera switched off', () {
      inCall((call) {
        call.join();

        call.wait(call.engine.switchToVideo());

        expect(call.videoSlot.sender.placements.last, placedOff(call.camera));
      }, kind: CallKind.voice);
    });

    test('a switch to video before joining puts the camera on its sender '
        'switched off', () {
      inCall((call) {
        call.wait(call.engine.switchToVideo());

        call.join();

        expect(call.videoSlot.sender.placements, [placedOff(call.camera)]);
      }, kind: CallKind.voice);
    });

    test('a rejoin puts the microphone and camera on the new senders '
        'switched off', () {
      inCall((call) {
        call.join();

        connectionFails(call);

        expect(call.backend.peerConnections, hasLength(2));
        final [audio, video] = call.pc.rtpTransceivers;
        expect(audio.sender.placements, [placedOff(call.microphone)]);
        expect(video.sender.placements, [placedOff(call.camera)]);
      });
    });
  });
}
