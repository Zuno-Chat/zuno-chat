import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/calls/module/call_provider_discovery.dart';
import 'package:zuno/core/calls/module/calls_module.dart';
import 'package:zuno_http/zuno_http.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/hybrid_fake_async.dart';

void main() {
  final at = DateTime(2026, 11, 7, 12);
  late CachingFakeDatabaseApi database;
  late List<http.Request> requests;
  late Future<http.Response> Function() answer;
  late List<CallProviderDiscovery> made;
  late Client client;

  http.Response provider(String? name) =>
      http.Response(jsonEncode({'provider': ?name}), 200);

  void saveOffer(
    Duration ago, {
    String user = '@me:example.org',
    String offer = 'cloudflare',
  }) {
    database.cache['zuno.calls_offer'] = (
      content: {
        'user_id': user,
        'saved_at': at.subtract(ago).millisecondsSinceEpoch,
        'offer': offer,
      },
      savedAt: at,
    );
  }

  CallProviderDiscovery build({bool loggedIn = false}) {
    final fake = FakeHttpClient((request) {
      requests.add(request);
      return answer();
    });
    client = buildTestClient(
      userId: '@me:example.org',
      database: database,
      httpClient: fake,
    )..homeserver = Uri.parse('https://example.org');
    if (loggedIn) client.bearerToken = 'token';
    final discovery = CallProviderDiscovery(client: client, httpClient: fake);
    client.bearerToken = 'token';
    made.add(discovery);
    return discovery;
  }

  setUp(() {
    database = CachingFakeDatabaseApi();
    requests = [];
    made = [];
    answer = () async => provider('cloudflare');
  });

  tearDown(() {
    for (final discovery in made) {
      discovery.dispose();
    }
  });

  Future<T> atNow<T>(Future<T> Function() body, [DateTime? now]) =>
      withClock(Clock.fixed(now ?? at), body);

  List<CallsOffer?> watch(CallProviderDiscovery discovery) {
    final seen = <CallsOffer?>[];
    final sub = discovery.offers.listen(seen.add);
    addTearDown(sub.cancel);
    return seen;
  }

  const retriesRunOut = Duration(seconds: 10);

  test(
    'livekit answer reads as livekit and is persisted',
    () => atNow(() async {
      answer = () async => provider('livekit');
      final d = build();
      expect(await d.current(), CallsOffer.livekit);
      expect(database.cache['zuno.calls_offer']!.content['offer'], 'livekit');
      final reloaded = build();
      expect(await reloaded.current(), CallsOffer.livekit);
      expect(requests, hasLength(1));
    }),
  );

  test(
    'cloudflare answer is cached and persisted',
    () => atNow(() async {
      final d = build();
      expect(await d.current(), CallsOffer.cloudflare);
      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/_synapse/client/zuno/calls/config');
      expect(requests.single.headers['Authorization'], 'Bearer token');
      expect(
        database.cache['zuno.calls_offer']!.content['offer'],
        'cloudflare',
      );
    }),
  );

  test(
    'a second current() makes no request',
    () => atNow(() async {
      final d = build();
      await d.current();
      await d.current();
      expect(requests, hasLength(1));
    }),
  );

  test(
    'a saved answer is read without a request',
    () => atNow(() async {
      saveOffer(const Duration(hours: 1));
      final d = build();
      expect(await d.current(), CallsOffer.cloudflare);
      await pumpEventQueue();
      expect(requests, isEmpty);
    }),
  );

  test(
    'a saved none is asked again, and the new answer reaches offers',
    () => atNow(() async {
      saveOffer(const Duration(hours: 1), offer: 'none');
      final d = build();
      final seen = watch(d);
      await pumpEventQueue();
      expect(seen, [CallsOffer.none]);

      expect(await d.current(), CallsOffer.cloudflare);
      await pumpEventQueue();

      expect(requests, hasLength(1));
      expect(seen, [CallsOffer.none, CallsOffer.cloudflare]);
      expect(await d.current(), CallsOffer.cloudflare);
      expect(requests, hasLength(1));
    }),
  );

  test(
    'a saved none the server repeats keeps calls hidden',
    () => atNow(() async {
      saveOffer(const Duration(hours: 1), offer: 'none');
      answer = () async => http.Response('{}', 404);
      final d = build();
      final seen = watch(d);
      await pumpEventQueue();

      expect(await d.current(), CallsOffer.none);
      await pumpEventQueue();

      expect(requests, hasLength(1));
      expect(seen, [CallsOffer.none]);
    }),
  );

  test('a saved none an unreachable server cannot replace stays', () {
    fakeAsync((async) {
      saveOffer(const Duration(hours: 1), offer: 'none');
      answer = () async =>
          throw NativeHttpException(HttpFailureKind.connectionLost, 'down');
      final d = build();
      final seen = watch(d);
      async.flushAll();

      expect(
        () => async.waitFor(d.current(), elapsing: retriesRunOut),
        throwsA(isA<NativeHttpException>()),
      );

      expect(requests, hasLength(3));
      expect(seen, [CallsOffer.none]);
      expect(
        database.cache['zuno.calls_offer']!.content['saved_at'],
        at.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
      );
    }, initialTime: at);
  });

  test(
    '404 reads as none',
    () => atNow(() async {
      answer = () async => http.Response('{}', 404);
      final d = build();
      expect(await d.current(), CallsOffer.none);
      expect(database.cache['zuno.calls_offer']!.content['offer'], 'none');
    }),
  );

  test(
    '404 M_UNRECOGNIZED reads as none',
    () => atNow(() async {
      answer = () async =>
          http.Response('{"errcode":"M_UNRECOGNIZED","error":"x"}', 404);
      final d = build();
      expect(await d.current(), CallsOffer.none);
    }),
  );

  test(
    'unknown provider and missing key read as none',
    () => atNow(() async {
      answer = () async => provider('mystery');
      final d = build();
      expect(await d.current(), CallsOffer.none);
      answer = () async => provider(null);
      expect(await d.refetch(), CallsOffer.none);
    }),
  );

  test(
    'a 200 answer that is not JSON reads as none and is not reported',
    () => atNow(() async {
      answer = () async => http.Response(
        '<!doctype html><html></html>',
        200,
        headers: {'content-type': 'text/html'},
      );
      final d = build();
      final seen = watch(d);
      await pumpEventQueue();
      expect(await reportsDuring(d.refreshIfStale), isEmpty);
      expect(await d.current(), CallsOffer.none);
      expect(seen, [null, CallsOffer.none]);
      expect(database.cache['zuno.calls_offer']!.content['offer'], 'none');
    }),
  );

  test('network failure stores nothing and keeps the previous answer', () {
    fakeAsync((async) {
      saveOffer(const Duration(hours: 1));
      final d = build();
      answer = () async =>
          throw NativeHttpException(HttpFailureKind.connectionLost, 'down');

      expect(
        () => async.waitFor(d.refetch(), elapsing: retriesRunOut),
        throwsA(isA<NativeHttpException>()),
      );
      final asked = requests.length;

      expect(async.waitFor(d.current()), CallsOffer.cloudflare);
      expect(requests, hasLength(asked));
      expect(
        database.cache['zuno.calls_offer']!.content['saved_at'],
        at.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
      );
    }, initialTime: at);
  });

  test(
    'a server failure on first discovery stores nothing',
    () => atNow(() async {
      answer = () async => http.Response('{}', 500);
      final d = build();
      await expectLater(d.current(), throwsA(isA<CallsModuleException>()));
      expect(await d.offers.first, isNull);
      expect(database.cache, isEmpty);
    }),
  );

  test(
    'concurrent current() calls share one request',
    () => atNow(() async {
      final gate = Completer<http.Response>();
      answer = () => gate.future;
      final d = build();
      final results = Future.wait([d.current(), d.current(), d.refetch()]);
      await pumpEventQueue();
      gate.complete(provider('cloudflare'));
      expect(await results, everyElement(CallsOffer.cloudflare));
      expect(requests, hasLength(1));
    }),
  );

  test('refreshIfStale requests only after a day', () async {
    saveOffer(Duration.zero);
    final d = build();
    await atNow(() => d.refreshIfStale(), at.add(const Duration(hours: 23)));
    expect(requests, isEmpty);
    await atNow(() => d.refreshIfStale(), at.add(const Duration(hours: 25)));
    expect(requests, hasLength(1));
  });

  test(
    'refreshIfStale requests when there is no answer',
    () => atNow(() async {
      final d = build();
      await d.refreshIfStale();
      expect(await d.current(), CallsOffer.cloudflare);
      expect(requests, hasLength(1));
    }),
  );

  test(
    'refreshIfStale asks again for a fresh saved none, and keeps the fresh '
    'answer it brings',
    () => atNow(() async {
      saveOffer(const Duration(hours: 1), offer: 'none');
      final d = build();
      final seen = watch(d);
      await pumpEventQueue();

      await d.refreshIfStale();
      await pumpEventQueue();

      expect(requests, hasLength(1));
      expect(seen, [CallsOffer.none, CallsOffer.cloudflare]);
      await d.refreshIfStale();
      expect(requests, hasLength(1));
    }),
  );

  test(
    'a fresh saved none the server fails to replace stays, unreported',
    () => atNow(() async {
      saveOffer(const Duration(hours: 1), offer: 'none');
      answer = () async => http.Response('{}', 500);
      final d = build();
      final seen = watch(d);
      await pumpEventQueue();

      expect(await reportsDuring(d.refreshIfStale), isEmpty);
      await pumpEventQueue();

      expect(requests, hasLength(1));
      expect(seen, [CallsOffer.none]);
    }),
  );

  test(
    'refreshIfStale never throws and skips server failures',
    () => atNow(() async {
      answer = () async => http.Response('{}', 500);
      final d = build();
      expect(await reportsDuring(d.refreshIfStale), isEmpty);
      answer = () async => throw StateError('broken');
      expect(await reportsDuring(d.refreshIfStale), [
        'discover the call provider',
      ]);
    }),
  );

  test(
    'refreshIfStale reports a client error from the module, and a 404 reads '
    'as none without a report',
    () => atNow(() async {
      answer = () async => http.Response('{"errcode": "M_FORBIDDEN"}', 403);
      final d = build();
      expect(await reportsDuring(d.refreshIfStale), [
        'discover the call provider',
      ]);
      answer = () async => http.Response('{}', 404);
      expect(await reportsDuring(d.refreshIfStale), isEmpty);
      expect(await d.offers.first, CallsOffer.none);
    }),
  );

  test(
    'an entry for another user reads as no answer',
    () => atNow(() async {
      saveOffer(Duration.zero, user: '@you:example.org');
      final d = build();
      await d.refreshIfStale();
      expect(await d.current(), CallsOffer.cloudflare);
      expect(requests, hasLength(1));
    }),
  );

  test(
    'an unknown saved name reads as no answer',
    () => atNow(() async {
      database.cache['zuno.calls_offer'] = (
        content: {
          'user_id': '@me:example.org',
          'saved_at': at.millisecondsSinceEpoch,
          'offer': 'mystery',
        },
        savedAt: at,
      );
      final d = build();
      expect(await d.current(), CallsOffer.cloudflare);
      expect(requests, hasLength(1));
    }),
  );

  test(
    'offers emits the saved answer first, then changes',
    () => atNow(() async {
      saveOffer(const Duration(hours: 1));
      final d = build();
      final seen = watch(d);
      await pumpEventQueue();
      expect(seen, [CallsOffer.cloudflare]);
      answer = () async => provider(null);
      await d.refetch();
      await pumpEventQueue();
      expect(seen, [CallsOffer.cloudflare, CallsOffer.none]);
    }),
  );

  test(
    'a refetch that brings the same offer emits nothing and refreshes when '
    'it was saved',
    () => atNow(() async {
      saveOffer(const Duration(hours: 1));
      final d = build();
      final seen = watch(d);
      await pumpEventQueue();

      expect(await d.refetch(), CallsOffer.cloudflare);
      await pumpEventQueue();

      expect(seen, [CallsOffer.cloudflare]);
      expect(
        database.cache['zuno.calls_offer']!.content['saved_at'],
        at.millisecondsSinceEpoch,
      );
    }),
  );

  test(
    'loggedOut drops the answer and emits null',
    () => atNow(() async {
      saveOffer(const Duration(hours: 1));
      final d = build();
      final seen = watch(d);
      await pumpEventQueue();
      client.onLoginStateChanged.add(LoginState.loggedOut);
      await pumpEventQueue();
      expect(seen, [CallsOffer.cloudflare, null]);
    }),
  );

  test(
    'loggedIn refreshes a missing answer',
    () => atNow(() async {
      final d = build();
      client.onLoginStateChanged.add(LoginState.loggedIn);
      await pumpEventQueue();
      expect(await d.current(), CallsOffer.cloudflare);
      expect(requests, hasLength(1));
    }),
  );

  test(
    'refetch requests again and replaces the answer',
    () => atNow(() async {
      final d = build();
      await d.current();
      answer = () async => provider(null);
      expect(await d.refetch(), CallsOffer.none);
      expect(requests, hasLength(2));
      expect(await d.offers.first, CallsOffer.none);
    }),
  );

  test(
    'construction on a logged-in client requests when there is no answer',
    () => atNow(() async {
      final d = build(loggedIn: true);
      await pumpEventQueue();
      expect(await d.current(), CallsOffer.cloudflare);
      expect(requests, hasLength(1));
    }),
  );

  test(
    'construction on a logged-in client with a fresh answer requests nothing',
    () => atNow(() async {
      saveOffer(const Duration(hours: 1));
      build(loggedIn: true);
      await pumpEventQueue();
      expect(requests, isEmpty);
    }),
  );

  test(
    'a login right after a logout gets its own request and answer',
    () => atNow(() async {
      final gate = Completer<http.Response>();
      answer = () => gate.future;
      final d = build();
      final old = d.current();
      await pumpEventQueue();
      expect(requests, hasLength(1));
      client.onLoginStateChanged.add(LoginState.loggedOut);
      await pumpEventQueue();
      answer = () async => provider(null);
      expect(await d.current(), CallsOffer.none);
      expect(requests, hasLength(2));
      gate.complete(provider('cloudflare'));
      await old;
      expect(await d.offers.first, CallsOffer.none);
    }),
  );

  test(
    'a listener that cancels before the answer loads leaks nothing',
    () => atNow(() async {
      final d = build();
      final sub = d.offers.listen((_) {});
      await sub.cancel();
      await pumpEventQueue();
      expect(requests, isEmpty);
    }),
  );
}
