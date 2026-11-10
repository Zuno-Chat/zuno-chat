import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/matrixrtc/call_peer_keys.dart';
import 'package:zuno/core/calls/matrixrtc/call_sender_key_event.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';

const _bob = VoipParticipantId(userId: '@bob:hs', deviceId: 'BOB');

SenderKey _key(int epoch, int gen) =>
    (epoch: epoch, gen: gen, key: Uint8List(32));

void main() {
  late CallPeerKeys keys;

  setUp(() => keys = CallPeerKeys());

  test('a first key under the sender\'s membership is applied at once', () {
    expect(keys.receive(_bob, _key(5, 1), epoch: 5)?.gen, 1);
  });

  test('within one membership, an older or equal key never replaces a newer '
      'one', () {
    keys.receive(_bob, _key(5, 3), epoch: 5);

    expect(keys.receive(_bob, _key(5, 3), epoch: 5), isNull);
    expect(keys.receive(_bob, _key(5, 2), epoch: 5), isNull);
    expect(keys.receive(_bob, _key(5, 4), epoch: 5)?.gen, 4);
  });

  test('a rejoin is heard whichever way its clock moved, and a late key from '
      'the session before it is not', () {
    keys.receive(_bob, _key(5, 9), epoch: 5);

    expect(keys.receive(_bob, _key(3, 1), epoch: 3)?.epoch, 3);
    expect(keys.receive(_bob, _key(5, 10), epoch: 3), isNull);
  });

  test('a key from a device not yet in the call is held, newest first, and '
      'applied once its membership appears', () {
    expect(keys.receive(_bob, _key(5, 3), epoch: null), isNull);
    keys.receive(_bob, _key(5, 2), epoch: null);

    expect(keys.joined(_bob, 4), isNull);
    expect(keys.joined(_bob, 5)?.gen, 3);
    expect(keys.joined(_bob, 5), isNull);
  });

  test('a key ahead of its new membership is held while the old one still '
      'shows', () {
    keys.receive(_bob, _key(5, 1), epoch: 5);

    expect(keys.receive(_bob, _key(2, 1), epoch: 5), isNull);

    expect(keys.joined(_bob, 2)?.epoch, 2);
  });

  test('a held key from another session gives way to the latest one', () {
    keys.receive(_bob, _key(5, 3), epoch: null);
    keys.receive(_bob, _key(2, 1), epoch: null);

    expect(keys.joined(_bob, 5), isNull);
    expect(keys.joined(_bob, 2)?.gen, 1);
  });

  test('at most eight devices are held for, and a new one pushes out the '
      'longest held', () {
    VoipParticipantId device(int i) =>
        VoipParticipantId(userId: '@u$i:hs', deviceId: 'D$i');
    for (var i = 0; i < 9; i++) {
      keys.receive(device(i), _key(1, 1), epoch: null);
    }

    expect(keys.joined(device(0), 1), isNull);
    for (var i = 1; i < 9; i++) {
      expect(keys.joined(device(i), 1), isNotNull);
    }
  });

  test('a device that sends again is held as the newest', () {
    VoipParticipantId device(int i) =>
        VoipParticipantId(userId: '@u$i:hs', deviceId: 'D$i');
    for (var i = 0; i < 8; i++) {
      keys.receive(device(i), _key(1, 1), epoch: null);
    }

    keys.receive(device(0), _key(1, 2), epoch: null);
    keys.receive(device(8), _key(1, 1), epoch: null);

    expect(keys.joined(device(0), 1)?.gen, 2);
    expect(keys.joined(device(1), 1), isNull);
  });

  test('a removed user\'s held and applied keys are dropped, and the devices '
      'whose applied keys went are named', () {
    const carol = VoipParticipantId(userId: '@carol:hs', deviceId: 'CAROL');
    keys.receive(_bob, _key(5, 1), epoch: 5);
    keys.receive(carol, _key(5, 1), epoch: null);

    expect(keys.forgetUsers({_bob.userId, carol.userId}), {_bob});
    expect(keys.joined(carol, 5), isNull);
    expect(keys.receive(_bob, _key(5, 1), epoch: 5)?.gen, 1);
  });

  test('a device under a new membership is reported as restarted once, and '
      'its next key starts over', () {
    keys.receive(_bob, _key(5, 9), epoch: 5);

    expect(keys.restarted(_bob, 5), isFalse);
    expect(keys.restarted(_bob, 6), isTrue);
    expect(keys.restarted(_bob, 6), isFalse);
    expect(keys.receive(_bob, _key(6, 1), epoch: 6)?.gen, 1);
  });
}
