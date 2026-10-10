import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/matrix/client_lease.dart';

import '../../helpers/native_method_calls.dart';
import '../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/client_lease_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall call) answer;
  late ClientLeases leases;

  setUp(() {
    calls = [];
    answer = (call) async => call.method == 'acquire' ? 'token-1' : null;
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return answer(call);
    });
    leases = ClientLeases(capabilities: androidCapabilities, channel: channel);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
  });

  Iterable<String> methods() => calls.map((c) => c.method);

  test('the app asks for its lease and waits at most five seconds', () async {
    final lease = await leases.acquire(ClientLeaseKind.app);

    expect(lease.token, 'token-1');
    expect(calls.single.arguments, {'kind': 'app', 'waitMs': 5000});
  });

  test('a background client asks for its lease and waits at most eight '
      'seconds', () async {
    await leases.acquire(ClientLeaseKind.background);

    expect(calls.single.arguments, {'kind': 'background', 'waitMs': 8000});
  });

  test('a background client the native side turns down is told so', () async {
    answer = (_) async => null;

    await expectLater(
      leases.acquire(ClientLeaseKind.background),
      throwsA(isA<ClientLeaseDenied>()),
    );
  });

  test('a lease is given back once, however often it is released', () async {
    final lease = await leases.acquire(ClientLeaseKind.background);

    await lease.release();
    await lease.release();

    expect(methods(), ['acquire', 'release']);
    expect(calls.last.arguments, {'token': 'token-1'});
  });

  test('where the platform has no lease, every client is let through with '
      'no native call', () async {
    leases = ClientLeases(
      capabilities: capabilitiesLike(androidCapabilities, clientLease: false),
      channel: channel,
    );

    final app = await leases.acquire(ClientLeaseKind.app);
    final background = await leases.acquire(ClientLeaseKind.background);
    await background.release();
    await leases.acquire(ClientLeaseKind.background);

    expect(app.token, isNull);
    expect(calls, isEmpty);
  });

  test('an engine without the native side lets the client through', () async {
    messenger.setMockMethodCallHandler(channel, null);

    final lease = await leases.acquire(ClientLeaseKind.background);

    expect(lease.token, isNull);
    await lease.release();
  });

  test('a native error lets the app start anyway', () async {
    answer = (_) async => throw PlatformException(code: 'broken');

    final lease = await leases.acquire(ClientLeaseKind.app);

    expect(lease.token, isNull);
  });

  test('an app start is never held up past its wait by a native side that '
      'does not answer', () {
    fakeAsync((async) {
      final never = Completer<Object?>();
      answer = (_) => never.future;
      ClientLease? lease;

      leases
          .acquire(ClientLeaseKind.app, wait: const Duration(seconds: 5))
          .then((granted) => lease = granted);
      async.elapse(const Duration(seconds: 8));

      expect(lease, isNotNull);
      expect(lease!.token, isNull);
    });
  });

  test('an app grant that comes after the wait is kept, since the app holds '
      'the client for good', () {
    fakeAsync((async) {
      final late = Completer<Object?>();
      answer = (call) =>
          call.method == 'acquire' ? late.future : Future.value(null);

      leases.acquire(ClientLeaseKind.app);
      async.elapse(const Duration(seconds: 8));
      late.complete('late-app-token');
      async.flushMicrotasks();

      expect(methods(), ['acquire']);
    });
  });

  test('a background client is turned down when the native side does not '
      'answer, and a late grant is given straight back', () {
    fakeAsync((async) {
      final late = Completer<Object?>();
      answer = (call) =>
          call.method == 'acquire' ? late.future : Future.value(null);
      Object? outcome;

      leases
          .acquire(ClientLeaseKind.background)
          .then<void>((_) => outcome = 'granted', onError: (e) => outcome = e);
      async.elapse(const Duration(seconds: 11));
      expect(outcome, isA<ClientLeaseDenied>());

      late.complete('late-token');
      async.flushMicrotasks();
      expect(methods(), ['acquire', 'release']);
      expect(calls.last.arguments, {'token': 'late-token'});
    });
  });

  test(
    'a yield from the native side is answered at once and passed on',
    () async {
      await leases.acquire(ClientLeaseKind.background);
      var yields = 0;
      final sub = leases.yieldRequests.listen((_) => yields++);
      addTearDown(sub.cancel);

      expect(await callFromNative(channel, 'yield'), isNull);
      await pumpEventQueue();

      expect(yields, 1);
    },
  );

  group('two background clients in one engine', () {
    test('the second waits until the first is let go', () async {
      var tokens = 0;
      answer = (call) async =>
          call.method == 'acquire' ? 'token-${++tokens}' : null;
      final first = await leases.acquire(ClientLeaseKind.background);
      ClientLease? second;

      final waiting = leases
          .acquire(ClientLeaseKind.background)
          .then((granted) => second = granted);
      await pumpEventQueue();
      expect(second, isNull);
      expect(methods(), ['acquire']);

      await first.release();
      await waiting;
      expect(second!.token, 'token-2');
      expect(methods(), ['acquire', 'release', 'acquire']);
    });

    test('the second is turned down if the first is not let go in time', () {
      fakeAsync((async) {
        leases.acquire(ClientLeaseKind.background);
        async.flushMicrotasks();
        Object? outcome;

        leases
            .acquire(
              ClientLeaseKind.background,
              wait: const Duration(seconds: 8),
            )
            .then<void>(
              (_) => outcome = 'granted',
              onError: (e) => outcome = e,
            );
        async.elapse(const Duration(seconds: 8));

        expect(outcome, isA<ClientLeaseDenied>());
        expect(methods(), ['acquire']);
      });
    });

    test('a turned-down client does not keep the next one waiting', () async {
      answer = (call) async => call.method == 'acquire' ? null : null;
      await expectLater(
        leases.acquire(ClientLeaseKind.background),
        throwsA(isA<ClientLeaseDenied>()),
      );
      answer = (call) async => call.method == 'acquire' ? 'token-9' : null;

      final lease = await leases
          .acquire(ClientLeaseKind.background)
          .timeout(const Duration(seconds: 1));

      expect(lease.token, 'token-9');
    });

    test('the app lease never waits behind them', () async {
      await leases.acquire(ClientLeaseKind.background);

      final app = await leases
          .acquire(ClientLeaseKind.app)
          .timeout(const Duration(seconds: 1));

      expect(app.token, 'token-1');
    });
  });
}
