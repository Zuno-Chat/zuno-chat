import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show KeyDerivationAlgorithm;
import 'package:zuno/core/calls/media/call_encryption.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';

import '../../../helpers/fake_webrtc.dart';

void main() {
  final key = Uint8List.fromList(List.filled(16, 7));
  final otherKey = Uint8List.fromList(List.filled(16, 9));
  const bob = VoipParticipantId(userId: '@bob:hs', deviceId: 'BOB');
  const carol = VoipParticipantId(userId: '@carol:hs', deviceId: 'CAROL');
  late List<String> journal;
  late FakeFrameCryptorFactory factory;
  late CallEncryption encryption;
  var changes = 0;

  setUp(() {
    journal = [];
    changes = 0;
    factory = FakeFrameCryptorFactory(journal: journal);
    encryption = CallEncryption(factory, onSendersChanged: () => changes++);
  });

  FakeSender senderWith(String id) => FakeSender(id, FakeTrack('audio', id));

  Future<void> sending([int slot = 1]) async {
    await encryption.setOwnKey(slot, key);
    await encryption.sendWithSlot(slot);
  }

  FakeKeyProvider providerOf(FakeFrameCryptor cryptor) =>
      cryptor.keyProvider! as FakeKeyProvider;

  test('our key goes into its slot of one provider set up as MSC4195 asks: '
      'HKDF, a key ring of 256 and LiveKit\'s salt, with no ratchet', () async {
    await encryption.setOwnKey(1, key);
    await encryption.setOwnKey(2, otherKey);

    expect(factory.keyProviders, hasLength(1));
    expect(factory.keyProviders.single.slots, {1: key, 2: otherKey});
    final options = factory.providerOptions.single;
    expect(options.sharedKey, isTrue);
    expect(options.ratchetWindowSize, 0);
    expect(options.keyDerivationAlgorithm, KeyDerivationAlgorithm.kHKDF);
    expect(options.keyRingSize, 256);
    expect(String.fromCharCodes(options.ratchetSalt), 'LKFrameEncryptionKey');
  });

  test('each participant gets its own provider', () async {
    await encryption.setOwnKey(1, key);
    await encryption.setPeerKey(bob, 1, otherKey);
    await encryption.setPeerKey(carol, 2, otherKey);
    await encryption.setPeerKey(bob, 2, key);

    expect(factory.keyProviders, hasLength(3));
    expect(factory.keyProviders[1].slots, {1: otherKey, 2: key});
    expect(factory.keyProviders[2].slots, {2: otherKey});
  });

  test('two keys for one new peer at once make one provider', () async {
    await Future.wait([
      encryption.setPeerKey(bob, 1, key),
      encryption.setPeerKey(bob, 2, otherKey),
    ]);

    expect(factory.keyProviders, hasLength(1));
    expect(factory.keyProviders.single.slots, {1: key, 2: otherKey});
  });

  test('our senders use our provider, with the send slot set before they are '
      'enabled', () async {
    await encryption.setPeerKey(bob, 1, otherKey);
    await sending(3);

    await encryption.wrapSender(
      'local-audio',
      senderWith('a'),
      stillWanted: () => true,
    );

    final cryptor = factory.cryptors.single;
    expect(cryptor.keyIndexAtEnable, 3);
    expect(providerOf(cryptor).slots, {3: key});
    expect(encryption.canSend, isTrue);
  });

  test('switching the send slot reaches every sender cryptor', () async {
    await sending();
    await encryption.wrapSender(
      'local-audio',
      senderWith('a'),
      stillWanted: () => true,
    );
    await encryption.wrapSender(
      'local-video',
      FakeSender('v', FakeTrack('video', 'v')),
      stillWanted: () => true,
    );
    await encryption.setOwnKey(2, otherKey);

    await encryption.sendWithSlot(2);

    expect(
      [for (final cryptor in factory.cryptors) cryptor.currentKeyIndex],
      [2, 2],
    );
  });

  test('a sender wrapped while the send slot switches ends on the new '
      'slot', () async {
    await sending();
    final gate = Completer<void>();
    factory.senderGate = gate;
    final wrapping = encryption.wrapSender(
      'local-audio',
      senderWith('a'),
      stillWanted: () => true,
    );
    await encryption.setOwnKey(2, otherKey);
    await encryption.sendWithSlot(2);

    gate.complete();
    await wrapping;

    expect(factory.cryptors.single.currentKeyIndex, 2);
  });

  test('nothing is sent until our send slot holds a key, and sending under '
      'an empty slot is refused', () async {
    final wrapped = await encryption.wrapSender(
      'local-audio',
      senderWith('a'),
      stillWanted: () => true,
    );
    await encryption.setOwnKey(1, key);
    final beforeSlot = await encryption.wrapSender(
      'local-audio',
      senderWith('a'),
      stillWanted: () => true,
    );
    await expectLater(encryption.sendWithSlot(2), throwsStateError);

    expect(wrapped, isFalse);
    expect(beforeSlot, isFalse);
    expect(encryption.canSend, isFalse);
    expect(factory.cryptors, isEmpty);
  });

  test('a receiver decrypts with its sender\'s provider only', () async {
    await encryption.setPeerKey(bob, 1, key);
    await encryption.setPeerKey(carol, 1, otherKey);

    await encryption.wrapReceiver(
      bob,
      'bob-audio',
      FakeReceiver('r', null),
      stillWanted: () => true,
    );

    expect(providerOf(factory.cryptors.single).slots, {1: key});
  });

  test('holdsKeyFor is false until that peer\'s key arrives', () async {
    expect(encryption.holdsKeyFor(bob), isFalse);

    await encryption.setPeerKey(bob, 1, key);

    expect(encryption.holdsKeyFor(bob), isTrue);
    expect(encryption.holdsKeyFor(carol), isFalse);
  });

  test('a peer without a key gets no receiver cryptor', () async {
    final wrapped = await encryption.wrapReceiver(
      carol,
      'carol-audio',
      FakeReceiver('c', null),
      stillWanted: () => true,
    );

    expect(wrapped, isFalse);
    expect(factory.keyProviders, isEmpty);
  });

  test(
    'key changes queued once the encryption is disposed do nothing',
    () async {
      final disposing = encryption.dispose();
      final keying = encryption.setPeerKey(bob, 1, key);
      await Future.wait([disposing, keying]);

      expect(factory.keyProviders, isEmpty);
      expect(encryption.holdsKeyFor(bob), isFalse);
    },
  );

  test(
    'forgetting a peer disposes its receivers before its provider',
    () async {
      await encryption.setPeerKey(bob, 1, key);
      await encryption.setPeerKey(carol, 1, key);
      final receiver = FakeReceiver('r', null);
      await encryption.wrapReceiver(
        bob,
        'bob-audio',
        receiver,
        stillWanted: () => true,
      );
      await encryption.wrapReceiver(
        carol,
        'carol-audio',
        FakeReceiver('c', null),
        stillWanted: () => true,
      );
      journal.clear();

      await encryption.forgetPeer(bob);

      expect(journal, ['bob-audio cryptor disposed', 'key provider disposed']);
      expect(encryption.holdsKeyFor(bob), isFalse);
      expect(encryption.decrypts('bob-audio', receiver), isFalse);
      expect(factory.liveLabels, {'carol-audio'});
    },
  );

  test('a receiver wrap still in flight when its peer is forgotten is '
      'dropped', () async {
    await encryption.setPeerKey(bob, 1, key);
    final gate = Completer<void>();
    factory.receiverGate = gate;
    final receiver = FakeReceiver('r', null);
    final wrapping = encryption.wrapReceiver(
      bob,
      'bob-video',
      receiver,
      stillWanted: () => true,
    );
    await pumpEventQueue();

    final forgetting = encryption.forgetPeer(bob);
    await pumpEventQueue();
    gate.complete();
    await Future.wait([wrapping, forgetting]);

    expect(factory.live, isEmpty);
    expect(encryption.decrypts('bob-video', receiver), isFalse);
  });

  test('a forgotten peer that sends a new key is heard again', () async {
    await encryption.setPeerKey(bob, 1, key);
    await encryption.forgetPeer(bob);

    await encryption.setPeerKey(bob, 2, otherKey);

    expect(encryption.holdsKeyFor(bob), isTrue);
  });

  test('a sender cryptor that cannot take its slot is disposed and the error '
      'surfaces', () async {
    await sending();
    factory.failKeyIndexFor.add('local-audio');

    await expectLater(
      encryption.wrapSender(
        'local-audio',
        senderWith('a'),
        stillWanted: () => true,
      ),
      throwsStateError,
    );

    expect(factory.cryptors.single.disposed, isTrue);
  });

  test('wrapSender twice on the same sender creates one cryptor', () async {
    await sending();
    final sender = senderWith('a');

    expect(
      await encryption.wrapSender(
        'local-audio',
        sender,
        stillWanted: () => true,
      ),
      isTrue,
    );
    expect(
      await encryption.wrapSender(
        'local-audio',
        sender,
        stillWanted: () => true,
      ),
      isTrue,
    );

    expect(factory.cryptors, hasLength(1));
    expect(factory.cryptors.single.isEnabled, isTrue);
    expect(encryption.encrypts('local-audio', sender), isTrue);
    expect(changes, 1);
  });

  test('wrapSender on a sender with no track wraps nothing', () async {
    await sending();

    final wrapped = await encryption.wrapSender(
      'local-video',
      FakeSender('v', null),
      stillWanted: () => true,
    );

    expect(wrapped, isFalse);
    expect(factory.cryptors, isEmpty);
  });

  test('a sender no longer wanted gets its cryptor disposed and is not '
      'wrapped', () async {
    await sending();
    final sender = senderWith('a');

    final wrapped = await encryption.wrapSender(
      'local-audio',
      sender,
      stillWanted: () => false,
    );

    expect(wrapped, isFalse);
    expect(factory.cryptors.single.disposed, isTrue);
    expect(encryption.encrypts('local-audio', sender), isFalse);
  });

  test(
    'a cryptor that fails to start is disposed and the error surfaces',
    () async {
      await sending();
      factory.failEnableFor.add('local-audio');

      await expectLater(
        encryption.wrapSender(
          'local-audio',
          senderWith('a'),
          stillWanted: () => true,
        ),
        throwsStateError,
      );
      expect(factory.cryptors.single.disposed, isTrue);
    },
  );

  test('encrypts is false for a replaced sender', () async {
    await sending();
    final first = senderWith('a');
    final second = senderWith('b');
    await encryption.wrapSender('local-audio', first, stillWanted: () => true);

    expect(encryption.encrypts('local-audio', first), isTrue);
    expect(encryption.encrypts('local-audio', second), isFalse);
    expect(encryption.encrypts('local-audio', null), isFalse);
    expect(encryption.encrypts('local-video', first), isFalse);
  });

  test(
    'wrapping a replacement sender disposes the cryptor it replaces',
    () async {
      await sending();
      final first = senderWith('a');
      final second = senderWith('b');
      await encryption.wrapSender(
        'local-audio',
        first,
        stillWanted: () => true,
      );

      await encryption.wrapSender(
        'local-audio',
        second,
        stillWanted: () => true,
      );

      expect(factory.cryptors.first.disposed, isTrue);
      expect(factory.cryptors.last.disposed, isFalse);
      expect(encryption.encrypts('local-audio', second), isTrue);
      expect(encryption.encrypts('local-audio', first), isFalse);
    },
  );

  test('a refused key disposes a provider created for it', () async {
    factory.refuseKey = true;

    await expectLater(encryption.setPeerKey(bob, 1, key), throwsStateError);

    expect(factory.keyProviders.single.disposed, isTrue);
    expect(encryption.holdsKeyFor(bob), isFalse);
  });

  test('a refused key leaves an existing provider alone', () async {
    await encryption.setOwnKey(1, key);
    factory.keyProviders.single.refuseKey = true;

    await expectLater(encryption.setOwnKey(2, key), throwsStateError);

    expect(factory.keyProviders.single.disposed, isFalse);
    await encryption.sendWithSlot(1);
    expect(encryption.canSend, isTrue);
  });

  test('wrapReceiver wraps once, and dropReceiver disposes it', () async {
    await encryption.setPeerKey(bob, 1, key);
    final receiver = FakeReceiver('r', null);

    await encryption.wrapReceiver(
      bob,
      'bob-audio',
      receiver,
      stillWanted: () => true,
    );
    await encryption.wrapReceiver(
      bob,
      'bob-audio',
      receiver,
      stillWanted: () => true,
    );

    expect(factory.cryptors, hasLength(1));
    expect(factory.cryptors.single.isEnabled, isTrue);

    await encryption.dropReceiver('bob-audio');

    expect(factory.cryptors.single.disposed, isTrue);
  });

  test('a different receiver for the same label replaces the old '
      'cryptor', () async {
    await encryption.setPeerKey(bob, 1, key);
    final first = FakeReceiver('r1', null);
    final second = FakeReceiver('r2', null);
    await encryption.wrapReceiver(
      bob,
      'bob-audio',
      first,
      stillWanted: () => true,
    );

    await encryption.wrapReceiver(
      bob,
      'bob-audio',
      second,
      stillWanted: () => true,
    );

    expect(factory.cryptors, hasLength(2));
    expect(factory.cryptors.first.disposed, isTrue);
    expect(factory.cryptors.last.disposed, isFalse);
  });

  test('the same receiver handed again as a new object keeps its one '
      'cryptor', () async {
    await encryption.setPeerKey(bob, 1, key);
    await encryption.wrapReceiver(
      bob,
      'bob-audio',
      FakeReceiver('r', null),
      stillWanted: () => true,
    );

    await encryption.wrapReceiver(
      bob,
      'bob-audio',
      FakeReceiver('r', null),
      stillWanted: () => true,
    );

    expect(factory.cryptors, hasLength(1));
    expect(factory.cryptors.single.disposed, isFalse);
  });

  test('two wraps of one sender in flight make one cryptor', () async {
    await sending();
    final gate = Completer<void>();
    factory.senderGate = gate;
    final sender = senderWith('a');

    final first = encryption.wrapSender(
      'local-audio',
      sender,
      stillWanted: () => true,
    );
    final second = encryption.wrapSender(
      'local-audio',
      sender,
      stillWanted: () => true,
    );
    gate.complete();

    expect(await second, isFalse);
    expect(await first, isTrue);
    expect(factory.cryptors, hasLength(1));
  });

  test('two wraps of one receiver in flight make one cryptor', () async {
    await encryption.setPeerKey(bob, 1, key);
    final gate = Completer<void>();
    factory.receiverGate = gate;
    final receiver = FakeReceiver('r', null);

    final first = encryption.wrapReceiver(
      bob,
      'bob-audio',
      receiver,
      stillWanted: () => true,
    );
    final second = encryption.wrapReceiver(
      bob,
      'bob-audio',
      receiver,
      stillWanted: () => true,
    );
    gate.complete();
    await Future.wait([first, second]);

    expect(factory.cryptors, hasLength(1));
    expect(factory.liveLabels, {'bob-audio'});
  });

  test('a cryptor made while the encryption is disposed is dropped', () async {
    await sending();
    await encryption.setPeerKey(bob, 1, key);
    final senders = Completer<void>();
    final receivers = Completer<void>();
    factory
      ..senderGate = senders
      ..receiverGate = receivers;
    final sender = senderWith('a');
    final wrappingSender = encryption.wrapSender(
      'local-audio',
      sender,
      stillWanted: () => true,
    );
    final wrappingReceiver = encryption.wrapReceiver(
      bob,
      'bob-audio',
      FakeReceiver('r', null),
      stillWanted: () => true,
    );

    await encryption.dispose();
    senders.complete();
    receivers.complete();
    await Future.wait([wrappingSender, wrappingReceiver]);

    expect(factory.cryptors, isNotEmpty);
    expect(factory.live, isEmpty);
    expect(encryption.encrypts('local-audio', sender), isFalse);
  });

  test(
    'wrapReceiver without a key, or when not wanted, leaves no cryptor',
    () async {
      await encryption.wrapReceiver(
        bob,
        'bob-audio',
        FakeReceiver('r', null),
        stillWanted: () => true,
      );
      await encryption.setPeerKey(bob, 1, key);
      await encryption.wrapReceiver(
        bob,
        'bob-video',
        FakeReceiver('r2', null),
        stillWanted: () => false,
      );

      expect(factory.liveLabels, isEmpty);
    },
  );

  test('forgetAll disposes every cryptor and keeps the providers', () async {
    await sending();
    await encryption.setPeerKey(bob, 1, key);
    final sender = senderWith('a');
    await encryption.wrapSender('local-audio', sender, stillWanted: () => true);
    await encryption.wrapReceiver(
      bob,
      'bob-audio',
      FakeReceiver('r', null),
      stillWanted: () => true,
    );

    await encryption.forgetAll();

    expect(factory.live, isEmpty);
    expect(factory.keyProviders.where((p) => p.disposed), isEmpty);
    expect(encryption.canSend, isTrue);
    expect(encryption.holdsKeyFor(bob), isTrue);
    expect(encryption.encrypts('local-audio', sender), isFalse);
  });

  test('dispose disposes cryptors before the providers', () async {
    await sending();
    await encryption.setPeerKey(bob, 1, key);
    await encryption.wrapSender(
      'local-audio',
      senderWith('a'),
      stillWanted: () => true,
    );
    await encryption.wrapReceiver(
      bob,
      'bob-audio',
      FakeReceiver('r', null),
      stillWanted: () => true,
    );
    journal.clear();

    await encryption.dispose();

    expect(journal, [
      'local-audio cryptor disposed',
      'bob-audio cryptor disposed',
      'key provider disposed',
      'key provider disposed',
    ]);
    expect(encryption.canSend, isFalse);
    expect(encryption.holdsKeyFor(bob), isFalse);
  });
}
