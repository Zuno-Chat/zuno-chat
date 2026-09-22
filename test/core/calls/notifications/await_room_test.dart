import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/notifications/await_room.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;

  setUp(() => client = buildTestClient(userId: '@me:example.org'));

  test('returns a room that is already there without waiting', () {
    final room = buildTestRoom(client, id: '!room:example.org');
    client.rooms.add(room);

    fakeAsync((async) {
      Room? found;
      awaitRoom(client, '!room:example.org').then((r) => found = r);
      async.flushMicrotasks();
      expect(found, same(room));
    });
  });

  test('waits for a room the client has not restored yet', () {
    fakeAsync((async) {
      Room? found;
      var completed = false;
      awaitRoom(client, '!room:example.org').then((r) {
        found = r;
        completed = true;
      });

      async.elapse(const Duration(milliseconds: 600));
      expect(completed, isFalse, reason: 'nothing to find yet');

      final room = buildTestRoom(client, id: '!room:example.org');
      client.rooms.add(room);
      async.elapse(const Duration(milliseconds: 300));

      expect(found, same(room));
    });
  });

  test('gives up on a room that never appears', () {
    fakeAsync((async) {
      Object? found = 'unset';
      awaitRoom(
        client,
        '!missing:example.org',
        timeout: const Duration(seconds: 2),
      ).then((r) => found = r);

      async.elapse(const Duration(seconds: 5));
      expect(found, isNull);
    });
  });

  test('keeps looking for the whole timeout before giving up', () {
    fakeAsync((async) {
      var completed = false;
      awaitRoom(
        client,
        '!late:example.org',
        timeout: const Duration(seconds: 2),
      ).then((_) => completed = true);

      async.elapse(const Duration(milliseconds: 1500));
      expect(completed, isFalse);

      final room = buildTestRoom(client, id: '!late:example.org');
      client.rooms.add(room);
      async.elapse(const Duration(milliseconds: 300));
      expect(completed, isTrue);
    });
  });
}
