import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/matrixrtc/call_key_courier.dart';
import 'package:zuno/core/calls/matrixrtc/call_sender_key_event.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';

import '../../../helpers/fake_device_keys.dart';
import '../../../helpers/to_device_recording_client.dart';

const _bob = '@bob:example.org';
const _carol = '@carol:example.org';
const _bobId = VoipParticipantId(userId: _bob, deviceId: 'BOB');
const _carolId = VoipParticipantId(userId: _carol, deviceId: 'CAROL');

SenderKey _key(int gen) => (epoch: 1, gen: gen, key: Uint8List(32));

void main() {
  late ToDeviceRecordingClient client;
  late CallKeyCourier courier;
  var stopped = false;

  setUp(() {
    stopped = false;
    client = ToDeviceRecordingClient();
    setSelfSignedTestDevices(client, _bob, ['BOB']);
    setSelfSignedTestDevices(client, _carol, ['CAROL']);
    courier = CallKeyCourier(
      client,
      callId: 'call1',
      baseDelay: const Duration(milliseconds: 10),
      maxDelay: const Duration(milliseconds: 10),
      stopped: () => stopped,
    );
  });

  List<int?> gensSentTo(String deviceId) => [
    for (final send in client.sent)
      if (send.deviceId == deviceId)
        parseSenderKeyContent(
          send.body.cast<String, Object?>(),
          callId: 'call1',
        )?.gen,
  ];

  test('each key goes to a device once', () {
    fakeAsync((async) {
      courier.send([_bobId], _key(1));
      async.flushMicrotasks();
      courier.send([_bobId], _key(1));
      async.flushMicrotasks();
      courier.send([_bobId], _key(2));
      async.flushMicrotasks();

      expect(gensSentTo('BOB'), [1, 2]);
      expect(client.sent.first.type, callSenderKeyEventType);
    });
  });

  test('send says whether the key went out to anyone', () {
    fakeAsync((async) {
      expect(courier.send([_bobId], _key(1)), isTrue);
      async.flushMicrotasks();

      expect(courier.send([_bobId], _key(1)), isFalse);
      expect(courier.send(const [], _key(2)), isFalse);
    });
  });

  test('a key for several devices goes out in one request', () {
    fakeAsync((async) {
      courier.send([_bobId, _carolId], _key(1));
      async.flushMicrotasks();

      expect(client.requests, 1);
      expect(gensSentTo('BOB'), [1]);
      expect(gensSentTo('CAROL'), [1]);
    });
  });

  test('a device the batch misses is retried alone while the others count '
      'as delivered', () {
    fakeAsync((async) {
      client.olm = true;
      client.openOlmSession('CAROL');
      courier.send([_bobId, _carolId], _key(1));
      async.flushMicrotasks();
      expect(gensSentTo('BOB'), isEmpty);
      expect(gensSentTo('CAROL'), [1]);

      client.openOlmSession('BOB');
      async.elapse(const Duration(seconds: 1));

      expect(gensSentTo('BOB'), [1]);
      expect(gensSentTo('CAROL'), [1]);
    });
  });

  test('a resend goes out again and still counts the device as holding our '
      'key', () {
    fakeAsync((async) {
      courier.send([_bobId], _key(1));
      async.flushMicrotasks();

      courier.send([_bobId], _key(1), resend: true);
      async.flushMicrotasks();

      expect(gensSentTo('BOB'), [1, 1]);
      expect(courier.forget(_bobId), isTrue);
    });
  });

  test('a resend the key policy refuses still counts the device as holding '
      'our key', () {
    fakeAsync((async) {
      courier.send([_bobId], _key(1));
      async.flushMicrotasks();
      testMasterKey(client, _bob);

      courier.send([_bobId], _key(1), resend: true);
      async.flushMicrotasks();

      expect(gensSentTo('BOB'), [1]);
      expect(courier.forget(_bobId), isTrue);
    });
  });

  test('a device the key policy refuses is never sent a key', () {
    fakeAsync((async) {
      testMasterKey(client, _bob);
      setTestDevices(client, _bob, {'BOB': null});

      expect(courier.refuses(_bobId), isTrue);
      courier.send([_bobId], _key(1));
      async.elapse(const Duration(seconds: 10));

      expect(client.tries, isEmpty);
    });
  });

  test('a device gone from an up-to-date device list counts as refused, so '
      'one signed out mid-call is treated like a blocked one', () {
    setSelfSignedTestDevices(client, _bob, []);

    expect(courier.refuses(_bobId), isTrue);
  });

  test('a device missing from a device list still out of date is not taken '
      'for refused', () {
    setTestDevices(client, _bob, {}, outdated: true);

    expect(courier.refuses(_bobId), isFalse);
  });

  test('a failed send is retried until it lands', () {
    fakeAsync((async) {
      client.unreachable.add('BOB');
      courier.send([_bobId], _key(1));
      async.flushMicrotasks();
      expect(client.sent, isEmpty);

      client.unreachable.clear();
      async.elapse(const Duration(seconds: 1));

      expect(client.sent, hasLength(1));
    });
  });

  test('forget says whether the device had our key, and stops a send in '
      'flight', () {
    fakeAsync((async) {
      courier.send([_bobId], _key(1));
      async.flushMicrotasks();

      expect(courier.forget(_bobId), isTrue);
      expect(courier.forget(_bobId), isFalse);

      client.unreachable.add('BOB');
      courier.send([_bobId], _key(2));
      async.flushMicrotasks();
      courier.forget(_bobId);
      client.unreachable.clear();
      async.elapse(const Duration(seconds: 10));

      expect(client.sent, hasLength(1));
    });
  });

  test('a device forgotten while our key is on its way may hold it, since '
      'the send can still land', () {
    fakeAsync((async) {
      client.hold = Completer<void>();
      courier.send([_bobId], _key(1));
      async.flushMicrotasks();

      expect(courier.forget(_bobId), isTrue);
    });
  });

  test('nothing is sent once the call has stopped', () {
    fakeAsync((async) {
      stopped = true;

      courier.send([_bobId], _key(1));
      async.elapse(const Duration(seconds: 10));

      expect(client.tries, isEmpty);
    });
  });
}
