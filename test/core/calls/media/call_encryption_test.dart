import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/media/call_encryption.dart';

import '../../../helpers/fake_webrtc.dart';

void main() {
  final key = Uint8List.fromList(List.filled(16, 7));
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

  test('setKey creates one provider with ratchetWindowSize 0 and the zuno '
      'salt', () async {
    await encryption.setKey(key);
    await encryption.setKey(key);

    expect(encryption.hasKey, isTrue);
    expect(factory.keyProviders, hasLength(1));
    expect(factory.keyProviders.single.sharedKeys, [key, key]);
    final options = factory.providerOptions.single;
    expect(options.sharedKey, isTrue);
    expect(options.ratchetWindowSize, 0);
    expect(String.fromCharCodes(options.ratchetSalt), 'zuno.calls.e2ee');
  });

  test('wrapSender twice on the same sender creates one cryptor', () async {
    await encryption.setKey(key);
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
  });

  test('wrapSender without a key returns false and creates nothing', () async {
    final wrapped = await encryption.wrapSender(
      'local-audio',
      senderWith('a'),
      stillWanted: () => true,
    );

    expect(wrapped, isFalse);
    expect(factory.cryptors, isEmpty);
  });

  test('wrapSender on a sender with no track wraps nothing', () async {
    await encryption.setKey(key);

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
    await encryption.setKey(key);
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
      await encryption.setKey(key);
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
    await encryption.setKey(key);
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
      await encryption.setKey(key);
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

    await expectLater(encryption.setKey(key), throwsStateError);

    expect(factory.keyProviders.single.disposed, isTrue);
    expect(encryption.hasKey, isFalse);
  });

  test('a refused key leaves an existing provider alone', () async {
    await encryption.setKey(key);
    factory.keyProviders.single.refuseKey = true;

    await expectLater(encryption.setKey(key), throwsStateError);

    expect(encryption.hasKey, isTrue);
    expect(factory.keyProviders.single.disposed, isFalse);
  });

  test('wrapReceiver wraps once, and dropReceiver disposes it', () async {
    await encryption.setKey(key);
    final receiver = FakeReceiver('r', null);

    await encryption.wrapReceiver(
      'bob-audio',
      receiver,
      stillWanted: () => true,
    );
    await encryption.wrapReceiver(
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
    await encryption.setKey(key);
    final first = FakeReceiver('r1', null);
    final second = FakeReceiver('r2', null);
    await encryption.wrapReceiver('bob-audio', first, stillWanted: () => true);

    await encryption.wrapReceiver('bob-audio', second, stillWanted: () => true);

    expect(factory.cryptors, hasLength(2));
    expect(factory.cryptors.first.disposed, isTrue);
    expect(factory.cryptors.last.disposed, isFalse);
  });

  test('the same receiver handed again as a new object keeps its one '
      'cryptor', () async {
    await encryption.setKey(key);
    await encryption.wrapReceiver(
      'bob-audio',
      FakeReceiver('r', null),
      stillWanted: () => true,
    );

    await encryption.wrapReceiver(
      'bob-audio',
      FakeReceiver('r', null),
      stillWanted: () => true,
    );

    expect(factory.cryptors, hasLength(1));
    expect(factory.cryptors.single.disposed, isFalse);
  });

  test('two wraps of one sender in flight make one cryptor', () async {
    await encryption.setKey(key);
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
    await encryption.setKey(key);
    final gate = Completer<void>();
    factory.receiverGate = gate;
    final receiver = FakeReceiver('r', null);

    final first = encryption.wrapReceiver(
      'bob-audio',
      receiver,
      stillWanted: () => true,
    );
    final second = encryption.wrapReceiver(
      'bob-audio',
      receiver,
      stillWanted: () => true,
    );
    gate.complete();
    await Future.wait([first, second]);

    expect(factory.cryptors, hasLength(1));
    expect(factory.liveLabels, {'bob-audio'});
  });

  test('a cryptor made while the provider is disposed is dropped', () async {
    await encryption.setKey(key);
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
      'bob-audio',
      FakeReceiver('r', null),
      stillWanted: () => true,
    );

    await encryption.dispose();
    senders.complete();
    receivers.complete();
    await Future.wait([wrappingSender, wrappingReceiver]);

    expect(factory.cryptors, hasLength(2));
    expect(factory.live, isEmpty);
    expect(encryption.encrypts('local-audio', sender), isFalse);
  });

  test('rolling back says senders changed only when it dropped one', () async {
    await encryption.setKey(key);
    await encryption.wrapSender(
      'local-audio',
      senderWith('a'),
      stillWanted: () => true,
    );
    final checkpoint = encryption.checkpoint();
    changes = 0;

    await encryption.rollBack(checkpoint);
    expect(changes, 0);

    await encryption.wrapSender(
      'local-video',
      senderWith('v'),
      stillWanted: () => true,
    );
    changes = 0;
    await encryption.rollBack(checkpoint);
    expect(changes, 1);
  });

  test(
    'wrapReceiver without a key, or when not wanted, leaves no cryptor',
    () async {
      await encryption.wrapReceiver(
        'bob-audio',
        FakeReceiver('r', null),
        stillWanted: () => true,
      );
      await encryption.setKey(key);
      await encryption.wrapReceiver(
        'bob-video',
        FakeReceiver('r2', null),
        stillWanted: () => false,
      );

      expect(factory.liveLabels, isEmpty);
    },
  );

  test('forgetAll disposes every cryptor and keeps the provider', () async {
    await encryption.setKey(key);
    final sender = senderWith('a');
    await encryption.wrapSender('local-audio', sender, stillWanted: () => true);
    await encryption.wrapReceiver(
      'bob-audio',
      FakeReceiver('r', null),
      stillWanted: () => true,
    );

    await encryption.forgetAll();

    expect(factory.live, isEmpty);
    expect(factory.keyProviders.single.disposed, isFalse);
    expect(encryption.hasKey, isTrue);
    expect(encryption.encrypts('local-audio', sender), isFalse);
  });

  test('dispose disposes cryptors before the provider', () async {
    await encryption.setKey(key);
    await encryption.wrapSender(
      'local-audio',
      senderWith('a'),
      stillWanted: () => true,
    );
    await encryption.wrapReceiver(
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
    ]);
    expect(encryption.hasKey, isFalse);
  });

  test('rolling back to a checkpoint drops what was added since and a new '
      'provider', () async {
    final checkpoint = encryption.checkpoint();
    await encryption.setKey(key);
    final sender = senderWith('a');
    await encryption.wrapSender('local-audio', sender, stillWanted: () => true);

    await encryption.rollBack(checkpoint);

    expect(factory.cryptors.single.disposed, isTrue);
    expect(factory.keyProviders.single.disposed, isTrue);
    expect(encryption.hasKey, isFalse);
    expect(encryption.encrypts('local-audio', sender), isFalse);
  });

  test('rolling back a first key drops the receivers wrapped with it, so the '
      'next key wraps them again', () async {
    final checkpoint = encryption.checkpoint();
    await encryption.setKey(key);
    final receiver = FakeReceiver('r', null);
    await encryption.wrapReceiver(
      'bob-audio',
      receiver,
      stillWanted: () => true,
    );

    await encryption.rollBack(checkpoint);

    expect(encryption.decrypts('bob-audio', receiver), isFalse);
    expect(factory.live, isEmpty);

    await encryption.setKey(key);
    await encryption.wrapReceiver(
      'bob-audio',
      receiver,
      stillWanted: () => true,
    );

    expect(encryption.decrypts('bob-audio', receiver), isTrue);
    expect(factory.live.single.participantId, 'bob-audio');
  });

  test('rolling back keeps what the checkpoint already held', () async {
    await encryption.setKey(key);
    final kept = senderWith('a');
    await encryption.wrapSender('local-audio', kept, stillWanted: () => true);
    final checkpoint = encryption.checkpoint();
    await encryption.wrapSender(
      'local-video',
      senderWith('v'),
      stillWanted: () => true,
    );

    await encryption.rollBack(checkpoint);

    expect(encryption.encrypts('local-audio', kept), isTrue);
    expect(factory.liveLabels, {'local-audio'});
    expect(encryption.hasKey, isTrue);
  });
}
