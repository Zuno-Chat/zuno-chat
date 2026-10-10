import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/sync_coordinator.dart';
import 'package:zuno/core/matrix/sync_request_canceller.dart';
import 'package:zuno/core/matrix/zuno_client.dart';

import '../../helpers/fake_sync_server.dart';
import '../../helpers/hybrid_fake_async.dart';

void main() {
  late FakeSyncServer server;
  late SyncingFakeDatabaseApi database;
  late ZunoClient client;
  late SyncCoordinator sync;
  late FakeAsync time;

  Future<void> flush() => time.settle();

  void act(void Function() action) => time.run((_) => action());

  Future<void> run(Future<void> Function() body) async {
    time = FakeAsync();
    act(() {
      server = FakeSyncServer();
      database = SyncingFakeDatabaseApi();
      final requests = SyncRequestCanceller(server);
      client = signInForSync(
        ZunoClient('test', database: database, httpClient: requests),
      );
      sync = client.syncCoordinator = SyncCoordinator(client, requests);
    });
    try {
      await body();
    } finally {
      act(sync.dispose);
      for (final open in server.waiting.toList()) {
        open.answer('end');
      }
      await flush();
    }
  }

  void syncTest(String description, Future<void> Function() body) =>
      test(description, () => run(body));

  Future<void> prime() async {
    act(() => unawaited(client.oneShotSync()));
    await flush();
    server.last.answer('s1');
    await flush();
  }

  HeldSync waitingOne() {
    expect(server.waiting, hasLength(1));
    return server.waiting.single;
  }

  group('the loop', () {
    syncTest('never comes from the SDK itself', () async {
      await prime();

      expect(server.syncs, hasLength(1));
      expect(server.waiting, isEmpty);
    });

    syncTest('keeps one 30 s long poll going in the foreground', () async {
      await prime();
      act(() => sync.set(SyncReason.foreground, true));
      await flush();

      final first = waitingOne();
      expect((first.since, first.timeout), ('s1', '30000'));

      first.answer('s2');
      await flush();

      final next = waitingOne();
      expect((next.since, next.timeout), ('s2', '30000'));
    });

    for (final reason in [SyncReason.liveShare, SyncReason.delivery]) {
      syncTest('long-polls for 90 s with only ${reason.name} held', () async {
        await prime();
        act(() => sync.set(reason, true));
        await flush();

        expect(waitingOne().timeout, '90000');
      });
    }

    syncTest('asks for no long poll on a first sync', () async {
      act(() => sync.set(SyncReason.foreground, true));
      await flush();

      expect(waitingOne().timeout, isNull);
    });

    syncTest('lets the request in flight finish once the last reason goes, and '
        'sends no more', () async {
      await prime();
      act(() => sync.set(SyncReason.foreground, true));
      await flush();
      final inFlight = waitingOne();

      act(() => sync.set(SyncReason.foreground, false));
      await flush();
      expect(inFlight.aborted, isFalse);

      inFlight.answer('s2');
      await flush();

      expect(server.waiting, isEmpty);
      expect(client.prevBatch, 's2');
      expect(sync.syncing, isFalse);
    });

    syncTest('pauses background reasons without network and resumes them '
        'when it returns', () async {
      await prime();
      act(() => sync.set(SyncReason.liveShare, true));
      await flush();

      act(() => sync.setNetworkAvailable(false));
      waitingOne().answer('s2');
      await flush();
      expect(server.waiting, isEmpty);

      act(() => sync.setNetworkAvailable(true));
      await flush();

      expect(waitingOne().since, 's2');
    });
  });

  group('a stale request', () {
    syncTest('is cancelled and sent again when the network returns', () async {
      await prime();
      act(() => sync.set(SyncReason.foreground, true));
      await flush();
      final stale = waitingOne();

      act(() => sync.setNetworkAvailable(false));
      act(() => sync.setNetworkAvailable(true));
      await flush();

      expect(stale.aborted, isTrue);
      expect(waitingOne().since, 's1');
    });

    syncTest('is cancelled and sent again when the app comes back to the '
        'foreground', () async {
      await prime();
      act(() => sync.set(SyncReason.foreground, true));
      await flush();
      final stale = waitingOne();

      act(() => sync.set(SyncReason.foreground, false));
      act(() => sync.set(SyncReason.foreground, true));
      await flush();

      expect(stale.aborted, isTrue);
      expect(waitingOne().since, 's1');
    });

    syncTest('is not the first sync of a launch, which the first foreground '
        'keeps', () async {
      act(() => unawaited(client.oneShotSync(timeout: Duration.zero)));
      await flush();
      final first = waitingOne();

      act(() => sync.set(SyncReason.foreground, true));
      await flush();

      expect(first.aborted, isFalse);
      expect(waitingOne(), same(first));
    });

    syncTest('is never taken for a long poll that got cut', () async {
      await prime();
      act(() => sync.set(SyncReason.liveShare, true));
      await flush();
      await time.advance(
        const Duration(seconds: 40),
        step: const Duration(seconds: 1),
      );

      act(() => sync.setNetworkAvailable(false));
      act(() => sync.setNetworkAvailable(true));
      await flush();

      expect(waitingOne().timeout, '90000');
    });
  });

  group('failures', () {
    syncTest('a long poll cut after 30 s or more drops to 30 s for the '
        'session', () async {
      await prime();
      act(() => sync.set(SyncReason.liveShare, true));
      await flush();
      await time.advance(
        const Duration(seconds: 40),
        step: const Duration(seconds: 1),
      );

      waitingOne().fail();
      await flush();
      expect(waitingOne().timeout, '30000');

      waitingOne().answer('s2');
      await flush();
      expect(waitingOne().timeout, '30000');
    });

    syncTest('a long poll that fails at once keeps its length', () async {
      await prime();
      act(() => sync.set(SyncReason.liveShare, true));
      await flush();
      await time.advance(const Duration(seconds: 1));

      waitingOne().fail();
      await flush();

      expect(waitingOne().timeout, '90000');
    });

    syncTest('background syncing backs off after repeated failures, until the '
        'network returns', () async {
      await prime();
      act(() => sync.set(SyncReason.liveShare, true));
      await flush();
      for (var i = 0; i < 3; i++) {
        waitingOne().fail();
        await flush();
      }

      await time.advance(
        const Duration(seconds: 9),
        step: const Duration(seconds: 1),
      );
      expect(server.waiting, isEmpty);

      act(() => sync.setNetworkAvailable(false));
      act(() => sync.setNetworkAvailable(true));
      await flush();

      expect(server.waiting, hasLength(1));
    });

    syncTest('the foreground never backs off', () async {
      await prime();
      act(() => sync.set(SyncReason.foreground, true));
      await flush();
      for (var i = 0; i < 5; i++) {
        waitingOne().fail();
        await flush();
      }

      expect(server.waiting, hasLength(1));
    });
  });

  group('a cache clear', () {
    syncTest('cancels the long poll, then sends one initial sync', () async {
      await prime();
      act(() => sync.set(SyncReason.foreground, true));
      await flush();
      final longPoll = waitingOne();

      act(() => unawaited(client.clearCache()));
      await flush();

      expect(longPoll.aborted, isTrue);
      expect(database.cacheClears, 1);
      expect(waitingOne().since, isNull);
    });

    syncTest('sends nothing while no reason is held', () async {
      await prime();

      act(() => unawaited(client.clearCache()));
      await flush();

      expect(database.cacheClears, 1);
      expect(server.waiting, isEmpty);
    });
  });

  group('signing out', () {
    syncTest('cancels the request in flight', () async {
      await prime();
      act(() => sync.set(SyncReason.foreground, true));
      await flush();
      final inFlight = waitingOne();

      act(() => unawaited(client.clear()));
      await flush();

      expect(inFlight.aborted, isTrue);
      expect(server.waiting, isEmpty);
    });

    syncTest('and back in leaves the SDK\'s own loop off', () async {
      await prime();
      act(() => unawaited(client.clear()));
      await flush();
      act(() {
        signInForSync(client);
        client.onLoginStateChanged.add(LoginState.loggedIn);
      });
      await flush();

      act(() => unawaited(client.oneShotSync()));
      await flush();
      waitingOne().answer('s1');
      await flush();
      expect(server.waiting, isEmpty);

      act(() => sync.set(SyncReason.foreground, true));
      await flush();
      expect(server.waiting, hasLength(1));
    });
  });

  group('a push catch-up', () {
    syncTest('syncs once at once while the loop is off', () async {
      await prime();
      await time.advance(
        const Duration(seconds: 20),
        step: const Duration(seconds: 1),
      );

      Future<void>? first;
      Future<void>? second;
      act(() {
        first = sync.catchUp();
        second = sync.catchUp();
      });
      await flush();

      expect(first, isNotNull);
      expect(second, same(first));
      expect(waitingOne().timeout, '0');
    });

    syncTest('skips a client that synced moments ago', () async {
      await prime();

      expect(sync.catchUp(), isNull);
    });

    syncTest('leaves a running sync to itself', () async {
      await prime();
      await time.advance(
        const Duration(seconds: 20),
        step: const Duration(seconds: 1),
      );
      act(() => sync.set(SyncReason.foreground, true));
      await flush();

      expect(sync.catchUp(), isNull);
    });
  });
}
