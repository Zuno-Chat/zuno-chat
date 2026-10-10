import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/matrix/zuno_client.dart';
import 'package:zuno/core/push/send_keep_awake.dart';

import '../../helpers/fake_matrix.dart';
import '../../helpers/hybrid_fake_async.dart';

class _Clock {
  final events = <String>[];

  SendKeepAwake keeper() => SendKeepAwake(
    acquire: (tag, timeoutMs) async => events.add('acquire $tag $timeoutMs'),
    release: (tag) async => events.add('release $tag'),
  );
}

void main() {
  test(
    'one background task covers overlapping sends and ends after a pause',
    () {
      fakeAsync((async) {
        final clock = _Clock();
        final keeper = clock.keeper();
        final first = Completer<void>();
        final second = Completer<void>();

        unawaited(keeper.hold(() => first.future));
        unawaited(keeper.hold(() => second.future));
        async.flushMicrotasks();
        first.complete();
        async.elapse(const Duration(seconds: 1));
        expect(clock.events, ['acquire zuno_send 25000']);

        second.complete();
        async.elapse(const Duration(milliseconds: 299));
        expect(clock.events, hasLength(1));
        async.elapse(const Duration(milliseconds: 1));
        expect(clock.events.last, 'release zuno_send');
      });
    },
  );

  test('a chunk that starts within the pause keeps the same task', () {
    fakeAsync((async) {
      final clock = _Clock();
      final keeper = clock.keeper();

      unawaited(keeper.hold(() async {}));
      async.elapse(const Duration(milliseconds: 50));
      unawaited(keeper.hold(() async {}));
      async.elapse(const Duration(seconds: 1));

      expect(clock.events, ['acquire zuno_send 25000', 'release zuno_send']);
    });
  });

  test('a failed send still lets the task go', () {
    fakeAsync((async) {
      final clock = _Clock();
      final keeper = clock.keeper();

      keeper.hold<void>(() async => throw StateError('offline')).ignore();
      async.elapse(const Duration(seconds: 1));

      expect(clock.events.last, 'release zuno_send');
    });
  });

  test('a client with a keeper holds the message send', () async {
    final clock = _Clock();
    final client = _client(keepAwake: clock.keeper());
    final time = FakeAsync();

    String? eventId;
    time.run((_) {
      client
          .sendMessage('!r:zuno.im', 'm.room.message', 'txn', {'body': 'hi'})
          .then((id) => eventId = id);
    });
    await time.advance(const Duration(milliseconds: 300));

    expect(eventId, r'$sent');
    expect(clock.events, ['acquire zuno_send 25000', 'release zuno_send']);
  });

  test('a client without a keeper sends as before', () async {
    final client = _client();

    expect(client.keepAwake, isNull);
    expect(
      await client.sendMessage('!r:zuno.im', 'm.room.message', 'txn', {
        'body': 'hi',
      }),
      r'$sent',
    );
  });
}

ZunoClient _client({SendKeepAwake? keepAwake}) =>
    ZunoClient(
        'test',
        database: FakeDatabaseApi(),
        httpClient: MockClient(
          (request) async => http.Response('{"event_id": "\$sent"}', 200),
        ),
        keepAwake: keepAwake,
      )
      ..homeserver = Uri.parse('https://zuno.im')
      ..accessToken = 'token';
