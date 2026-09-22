import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/connection_monitor.dart';

class _Harness {
  final network = StreamController<bool>();
  final sync = StreamController<SyncStatusUpdate>();
  final probes = <Completer<bool>>[];
  late final ConnectionMonitor monitor = ConnectionMonitor(
    networkAvailable: network.stream,
    syncStatus: sync.stream,
    probe: () {
      final probe = Completer<bool>();
      probes.add(probe);
      return probe.future;
    },
  );

  ConnectionStatus get status => monitor.status;

  void syncError(Exception exception) => sync.add(
    SyncStatusUpdate(SyncStatus.error, error: SdkError(exception: exception)),
  );

  void connectionError() => syncError(SyncConnectionException('down'));

  void syncStarted() =>
      sync.add(SyncStatusUpdate(SyncStatus.waitingForResponse));

  void syncFinished() => sync.add(SyncStatusUpdate(SyncStatus.finished));

  void answerProbe(bool reachable) => probes.last.complete(reachable);
}

void _run(void Function(FakeAsync async, _Harness h) body) {
  fakeAsync((async) {
    final h = _Harness();
    h.monitor;
    async.flushMicrotasks();
    body(async, h);
    unawaited(h.monitor.dispose());
    async.flushMicrotasks();
  });
}

void _loseNetwork(FakeAsync async, _Harness h) {
  h.network.add(false);
  async.elapse(noInternetDelay + const Duration(milliseconds: 1));
}

void _becomeUnreachable(FakeAsync async, _Harness h) {
  h.connectionError();
  async.flushMicrotasks();
  h.answerProbe(false);
  async.flushMicrotasks();
}

void main() {
  test('starts online before anything is known', () {
    _run((async, h) => expect(h.status, ConnectionStatus.online));
  });

  group('no internet', () {
    test('reports no internet only once the network stays gone for the '
        'delay', () {
      _run((async, h) {
        h.network.add(false);
        async.elapse(noInternetDelay - const Duration(milliseconds: 100));
        expect(h.status, ConnectionStatus.online);
        async.elapse(const Duration(milliseconds: 200));
        expect(h.status, ConnectionStatus.noInternet);
      });
    });

    test('a network blip shorter than the delay never leaves online', () {
      _run((async, h) {
        h.network.add(false);
        async.elapse(const Duration(milliseconds: 500));
        h.network.add(true);
        async.elapse(const Duration(seconds: 10));
        expect(h.status, ConnectionStatus.online);
        expect(h.probes, isEmpty);
      });
    });

    test('network coming back keeps no internet until a probe confirms the '
        'homeserver answers', () {
      _run((async, h) {
        _loseNetwork(async, h);
        h.network.add(true);
        async.flushMicrotasks();
        expect(h.status, ConnectionStatus.noInternet);
        expect(h.probes, hasLength(1));
        h.answerProbe(true);
        async.flushMicrotasks();
        expect(h.status, ConnectionStatus.online);
      });
    });

    test('network back but the probe fails reports unreachable', () {
      _run((async, h) {
        _loseNetwork(async, h);
        h.network.add(true);
        async.flushMicrotasks();
        h.answerProbe(false);
        async.flushMicrotasks();
        expect(h.status, ConnectionStatus.unreachable);
      });
    });

    test('sync failures while the network is gone never probe', () {
      _run((async, h) {
        _loseNetwork(async, h);
        h.connectionError();
        h.connectionError();
        async.elapse(const Duration(seconds: 30));
        expect(h.probes, isEmpty);
        expect(h.status, ConnectionStatus.noInternet);
      });
    });

    test('a sync started after the network was reported gone that succeeds '
        'clears no internet', () {
      _run((async, h) {
        _loseNetwork(async, h);
        h.syncStarted();
        h.syncFinished();
        async.flushMicrotasks();
        expect(h.status, ConnectionStatus.online);
      });
    });

    test('a sync already in flight when the network dropped does not clear '
        'no internet', () {
      _run((async, h) {
        h.syncStarted();
        async.flushMicrotasks();
        _loseNetwork(async, h);
        h.syncFinished();
        async.flushMicrotasks();
        expect(h.status, ConnectionStatus.noInternet);
      });
    });
  });

  group('unreachable', () {
    test('a stalled sync confirmed by a failed probe reports unreachable', () {
      _run((async, h) {
        h.syncError(TimeoutException('stalled'));
        async.flushMicrotasks();
        expect(h.probes, hasLength(1));
        expect(h.status, ConnectionStatus.online);
        h.answerProbe(false);
        async.flushMicrotasks();
        expect(h.status, ConnectionStatus.unreachable);
      });
    });

    test('a connection error the probe contradicts stays online', () {
      _run((async, h) {
        h.connectionError();
        async.flushMicrotasks();
        h.answerProbe(true);
        async.elapse(const Duration(seconds: 30));
        expect(h.status, ConnectionStatus.online);
        expect(h.probes, hasLength(1));
      });
    });

    test('an error response from the homeserver never probes', () {
      _run((async, h) {
        h.syncError(MatrixException.fromJson({'errcode': 'M_UNKNOWN'}));
        async.elapse(const Duration(seconds: 30));
        expect(h.probes, isEmpty);
        expect(h.status, ConnectionStatus.online);
      });
    });

    test('failures arriving while a probe runs do not start another', () {
      _run((async, h) {
        h.connectionError();
        h.connectionError();
        h.connectionError();
        async.flushMicrotasks();
        expect(h.probes, hasLength(1));
      });
    });

    test('reprobes with growing delays, capped at the maximum', () {
      _run((async, h) {
        _becomeUnreachable(async, h);
        final gaps = <Duration>[];
        for (var i = 0; i < 5; i++) {
          final before = h.probes.length;
          var waited = Duration.zero;
          while (h.probes.length == before) {
            async.elapse(const Duration(milliseconds: 500));
            waited += const Duration(milliseconds: 500);
          }
          gaps.add(waited);
          h.answerProbe(false);
          async.flushMicrotasks();
        }
        expect(gaps, [
          firstReprobeDelay,
          firstReprobeDelay * 2,
          firstReprobeDelay * 4,
          maxReprobeDelay,
          maxReprobeDelay,
        ]);
      });
    });

    test('recovers as soon as a reprobe succeeds', () {
      _run((async, h) {
        _becomeUnreachable(async, h);
        async.elapse(firstReprobeDelay);
        h.answerProbe(true);
        async.flushMicrotasks();
        expect(h.status, ConnectionStatus.online);
      });
    });

    test('a successful sync clears unreachable at once and a late failed '
        'probe is ignored', () {
      _run((async, h) {
        _becomeUnreachable(async, h);
        async.elapse(firstReprobeDelay);
        final pending = h.probes.last;
        h.syncFinished();
        async.flushMicrotasks();
        expect(h.status, ConnectionStatus.online);
        pending.complete(false);
        async.elapse(const Duration(seconds: 30));
        expect(h.status, ConnectionStatus.online);
        expect(h.probes, hasLength(2));
      });
    });
  });

  group('foreground', () {
    test('no reprobes while in the background', () {
      _run((async, h) {
        _becomeUnreachable(async, h);
        h.monitor.setForeground(false);
        async.elapse(const Duration(minutes: 5));
        expect(h.probes, hasLength(1));
      });
    });

    test('sync failures in the background never probe', () {
      _run((async, h) {
        h.monitor.setForeground(false);
        h.connectionError();
        async.elapse(const Duration(seconds: 30));
        expect(h.probes, isEmpty);
      });
    });

    test('returning to the foreground probes at once when not online', () {
      _run((async, h) {
        _becomeUnreachable(async, h);
        h.monitor.setForeground(false);
        h.monitor.setForeground(true);
        async.flushMicrotasks();
        expect(h.probes, hasLength(2));
        h.answerProbe(true);
        async.flushMicrotasks();
        expect(h.status, ConnectionStatus.online);
      });
    });

    test('returning to the foreground while online does not probe', () {
      _run((async, h) {
        h.monitor.setForeground(false);
        h.monitor.setForeground(true);
        async.flushMicrotasks();
        expect(h.probes, isEmpty);
      });
    });
  });

  test('statuses emits the current status first, then each change once', () {
    _run((async, h) {
      _becomeUnreachable(async, h);
      final seen = <ConnectionStatus>[];
      final sub = h.monitor.statuses.listen(seen.add);
      async.flushMicrotasks();
      h.syncFinished();
      h.syncFinished();
      async.flushMicrotasks();
      expect(seen, [ConnectionStatus.unreachable, ConnectionStatus.online]);
      unawaited(sub.cancel());
    });
  });

  test('dispose cancels pending timers', () {
    fakeAsync((async) {
      final h = _Harness();
      h.monitor;
      _becomeUnreachable(async, h);
      h.network.add(false);
      async.flushMicrotasks();
      unawaited(h.monitor.dispose());
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty);
    });
  });
}
