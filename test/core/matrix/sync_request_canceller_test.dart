import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:zuno/core/matrix/sync_request_canceller.dart';

import '../../helpers/fake_sync_server.dart';

final _sync = Uri.parse(
  'https://example.org/_matrix/client/v3/sync?since=s1&timeout=30000',
);

void main() {
  late FakeSyncServer server;
  late SyncRequestCanceller requests;

  setUp(() {
    server = FakeSyncServer();
    requests = SyncRequestCanceller(server);
  });

  http.Request syncRequest() =>
      http.Request('GET', _sync)..headers['authorization'] = 'Bearer token';

  test('cancels a /sync request still waiting for its response', () async {
    final response = requests.send(syncRequest());
    await settleSync();

    expect(requests.cancel(), isTrue);

    await expectLater(response, throwsA(isA<http.RequestAbortedException>()));
    expect(server.waiting, isEmpty);
  });

  test(
    'cancels every /sync request still waiting, not only the last',
    () async {
      final first = requests.send(syncRequest());
      final second = requests.send(syncRequest());
      await settleSync();

      expect(requests.cancel(), isTrue);

      await expectLater(first, throwsA(isA<http.RequestAbortedException>()));
      await expectLater(second, throwsA(isA<http.RequestAbortedException>()));
      expect(server.waiting, isEmpty);
    },
  );

  test('sends a cancellable request with the original headers', () async {
    final response = requests.send(syncRequest());
    await settleSync();

    expect(server.last.headers['authorization'], 'Bearer token');
    expect(server.last.since, 's1');
    server.last.answer('s2');
    await response;
  });

  test('leaves an answered request alone', () async {
    final response = requests.send(syncRequest());
    await settleSync();
    server.last.answer('s2');
    await response;

    expect(requests.cancel(), isFalse);
  });

  test('never cancels other requests', () async {
    final response = requests.send(
      http.Request('POST', Uri.parse('https://example.org/x/filter')),
    );

    expect(requests.cancel(), isFalse);
    expect((await response).statusCode, 200);
  });

  test('while paused, refuses a /sync request at once and cancels the one '
      'waiting', () async {
    final waiting = requests.send(syncRequest());
    await settleSync();

    requests.pause();

    await expectLater(waiting, throwsA(isA<http.RequestAbortedException>()));
    await expectLater(
      requests.send(syncRequest()),
      throwsA(isA<http.RequestAbortedException>()),
    );
    expect(server.syncs, hasLength(1));

    requests.resume();
    final next = requests.send(syncRequest());
    await settleSync();
    expect(server.waiting, hasLength(1));
    server.last.answer('s2');
    await next;
  });
}
