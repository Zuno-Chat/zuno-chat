import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/room_mute.dart';

import '../../helpers/fake_http.dart';
import '../../helpers/fake_matrix.dart';

void main() {
  late List<String> writes;
  late bool refuse;
  Completer<void>? holdWrites;
  late Client client;
  late Room room;

  setUp(() {
    writes = [];
    refuse = false;
    holdWrites = null;
    client =
        buildTestClient(
            userId: '@me:example.org',
            httpClient: FakeHttpClient((request) async {
              if (request.url.path.contains('/pushrules/')) {
                writes.add(request.method);
                if (holdWrites case final hold?) await hold.future;
                if (refuse) {
                  return http.Response(
                    '{"errcode":"M_FORBIDDEN","error":"no"}',
                    403,
                  );
                }
              }
              return http.Response('{}', 200);
            }),
          )
          ..homeserver = Uri.parse('https://example.org')
          ..accessToken = 'token';
    room = buildTestRoom(client)..membership = Membership.join;
  });

  void serverSaysMuted(bool muted) {
    final rules = BasicEvent(
      type: 'm.push_rules',
      content: {
        'global': {
          'override': [
            if (muted)
              {
                'rule_id': room.id,
                'default': false,
                'enabled': true,
                'actions': <Object>[],
                'conditions': [
                  {'kind': 'event_match', 'key': 'room_id', 'pattern': room.id},
                ],
              },
          ],
        },
      },
    );
    client.accountData['m.push_rules'] = rules;
    client.onSync.add(SyncUpdate(nextBatch: 's', accountData: [rules]));
  }

  test('a rules sync that lands mid-write does not count as the answer', () {
    fakeAsync((async) {
      holdWrites = Completer<void>();
      setRoomMuted(room, true);
      async.flushMicrotasks();

      serverSaysMuted(false);
      async.flushMicrotasks();
      holdWrites!.complete();
      async.flushMicrotasks();

      expect(isRoomMuted(room), isTrue);

      serverSaysMuted(true);
      async.flushMicrotasks();

      expect(isRoomMuted(room), isTrue);
      expect(isRoomMuteSettling(room), isFalse);
    });
  });

  test('a room reads as muted at once, before the server confirms it', () {
    fakeAsync((async) {
      setRoomMuted(room, true);
      async.flushMicrotasks();

      expect(isRoomMuted(room), isTrue);
      expect(isRoomMuteSettling(room), isTrue);
      expect(writes, ['PUT']);

      serverSaysMuted(true);
      async.flushMicrotasks();

      expect(isRoomMuted(room), isTrue);
      expect(isRoomMuteSettling(room), isFalse);
    });
  });

  test('a second change waits until the first has settled', () {
    fakeAsync((async) {
      setRoomMuted(room, true);
      async.flushMicrotasks();
      setRoomMuted(room, false);
      async.flushMicrotasks();

      expect(writes, ['PUT']);
      expect(isRoomMuted(room), isTrue);

      serverSaysMuted(true);
      async.flushMicrotasks();
      setRoomMuted(room, false);
      async.flushMicrotasks();

      expect(writes, ['PUT', 'DELETE']);
      expect(isRoomMuted(room), isFalse);
      serverSaysMuted(false);
      async.flushMicrotasks();
      expect(isRoomMuted(room), isFalse);
    });
  });

  test('a refused change falls back to what the server has, and fails', () {
    fakeAsync((async) {
      refuse = true;
      Object? failure;
      setRoomMuted(room, true).then(
        (_) {},
        onError: (Object e) {
          failure = e;
        },
      );
      async.flushMicrotasks();

      expect(failure, isA<MatrixException>());
      expect(isRoomMuted(room), isFalse);
      expect(isRoomMuteSettling(room), isFalse);
    });
  });

  test('without word from the server it stops settling but still reads as '
      'asked, until the rules arrive', () {
    fakeAsync((async) {
      var done = false;
      setRoomMuted(room, true).then((_) => done = true);
      async.elapse(const Duration(seconds: 10));

      expect(done, isTrue);
      expect(isRoomMuteSettling(room), isFalse);
      expect(isRoomMuted(room), isTrue);

      serverSaysMuted(false);
      async.flushMicrotasks();
      expect(isRoomMuted(room), isFalse);
    });
  });

  test('asking for what the server already has settles at once', () {
    fakeAsync((async) {
      serverSaysMuted(true);
      async.flushMicrotasks();
      var done = false;
      setRoomMuted(room, true).then((_) => done = true);
      async.flushMicrotasks();

      expect(done, isTrue);
      expect(writes, isEmpty);
      expect(isRoomMuteSettling(room), isFalse);
      expect(isRoomMuted(room), isTrue);
    });
  });
}
