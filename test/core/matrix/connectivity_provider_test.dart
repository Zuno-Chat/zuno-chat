import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart' show FlutterError, FlutterErrorDetails;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/connection_monitor.dart';
import 'package:zuno/core/matrix/connectivity_provider.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/platform/app_platform.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isHomeserverReachable', () {
    late List<Uri> requested;

    Client clientAnswering(Future<http.Response> Function() answer) {
      requested = [];
      final client = buildTestClient(
        httpClient: MockClient((request) {
          requested.add(request.url);
          return answer();
        }),
      );
      client.homeserver = Uri.parse('https://example.org');
      return client;
    }

    test(
      'a versions response is reachable, fetched fresh every time',
      () async {
        final client = clientAnswering(
          () async => http.Response('{"versions":["v1.11"]}', 200),
        );

        expect(await isHomeserverReachable(client), isTrue);
        expect(await isHomeserverReachable(client), isTrue);
        expect(requested, [
          Uri.parse('https://example.org/_matrix/client/versions'),
          Uri.parse('https://example.org/_matrix/client/versions'),
        ]);
      },
    );

    test('any answer below 500 means the homeserver is there', () async {
      final client = clientAnswering(() async => http.Response('', 404));

      expect(await isHomeserverReachable(client), isTrue);
    });

    test(
      'a 5xx from a proxy in front of a down homeserver is unreachable',
      () async {
        final client = clientAnswering(
          () async => http.Response('<html>', 502),
        );

        expect(await isHomeserverReachable(client), isFalse);
      },
    );

    test('a connection error is unreachable', () async {
      final client = clientAnswering(
        () async => throw http.ClientException('refused'),
      );

      expect(await isHomeserverReachable(client), isFalse);
    });

    test('a request that never answers is unreachable after the timeout', () {
      fakeAsync((async) {
        final client = clientAnswering(() => Completer<http.Response>().future);
        bool? reachable;
        unawaited(isHomeserverReachable(client).then((r) => reachable = r));

        async.elapse(homeserverProbeTimeout - const Duration(seconds: 1));
        expect(reachable, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(reachable, isFalse);
      });
    });
  });

  group('isOfflineProvider', () {
    test('goes offline once the network stays gone, and back online once a '
        'sync succeeds', () {
      fakeAsync((async) {
        final network = StreamController<bool>();
        final client = buildTestClient(
          httpClient: MockClient((_) => Completer<http.Response>().future),
        );
        client.homeserver = Uri.parse('https://example.org');
        final container = ProviderContainer(
          overrides: [
            matrixClientProvider.overrideWithValue(client),
            networkAvailabilityProvider.overrideWithValue(network.stream),
          ],
        );
        final values = <bool>[];
        container.listen<AsyncValue<bool>>(isOfflineProvider, (_, next) {
          final value = next.value;
          if (value != null) values.add(value);
        }, fireImmediately: true);
        async.flushMicrotasks();

        network.add(false);
        async.elapse(noInternetDelay + const Duration(seconds: 1));
        expect(
          container.read(connectionStatusProvider).value,
          ConnectionStatus.noInternet,
        );

        network.add(true);
        async.elapse(Duration.zero);
        expect(values, [false, true]);

        client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.finished));
        async.elapse(Duration.zero);
        expect(values, [false, true, false]);

        container.dispose();
        async.flushMicrotasks();
      });
    });

    test('unreachable and no internet both count as offline', () {
      for (final status in ConnectionStatus.values) {
        final container = ProviderContainer(
          overrides: [
            connectionStatusProvider.overrideWithValue(AsyncData(status)),
          ],
        );
        addTearDown(container.dispose);
        expect(
          container.read(isOfflineProvider).value,
          status != ConnectionStatus.online,
        );
      }
    });
  });

  test('without a handler of its own, a test gets a silent network stream '
      'instead of a plugin error', () async {
    expect(ambientCapabilities.networkAvailabilityEvents, isTrue);
    final errors = <FlutterErrorDetails>[];
    final reportError = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = reportError);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final events = <bool>[];

    final subscription = container
        .read(networkAvailabilityProvider)
        .listen(events.add);
    await pumpEventQueue();
    await subscription.cancel();

    expect(events, isEmpty);
    expect(errors, isEmpty);
  });

  group('networkAvailabilityProvider', () {
    const networkChannel = EventChannel('zuno/network');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late int listens;

    setUp(() {
      listens = 0;
      messenger.setMockStreamHandler(
        networkChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            listens++;
            events.success(false);
            events.success(true);
            events.endOfStream();
          },
        ),
      );
    });

    tearDown(() => messenger.setMockStreamHandler(networkChannel, null));

    test('with android capabilities it forwards the native events', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(await container.read(networkAvailabilityProvider).toList(), [
        false,
        true,
      ]);
      expect(listens, 1);
    });

    test('without network events it stays empty and never listens', () async {
      final container = ProviderContainer(
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(
            capabilitiesFor(AppPlatform.ios),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container.read(networkAvailabilityProvider).toList(),
        isEmpty,
      );
      expect(listens, 0);
    });
  });

  group('becameOnline', () {
    test('offline to online is the reconnect edge', () {
      expect(
        becameOnline(const AsyncData(true), const AsyncData(false)),
        isTrue,
      );
    });

    test('online to online is not a reconnect', () {
      expect(
        becameOnline(const AsyncData(false), const AsyncData(false)),
        isFalse,
      );
    });

    test('online to offline is not a reconnect', () {
      expect(
        becameOnline(const AsyncData(false), const AsyncData(true)),
        isFalse,
      );
    });

    test('offline to offline is not a reconnect', () {
      expect(
        becameOnline(const AsyncData(true), const AsyncData(true)),
        isFalse,
      );
    });

    test('no previous emission (first build) is never a reconnect', () {
      expect(becameOnline(null, const AsyncData(false)), isFalse);
    });
  });
}
