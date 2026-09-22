import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush/unifiedpush.dart';
import 'package:matrix/matrix.dart';
import 'package:unifiedpush_platform_interface/data/public_key_set.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart';
import 'package:zuno/core/notifications/unified_push_delivery_provider.dart';
import 'package:zuno/core/push/unified_push_pusher.dart';
import 'package:zuno/core/push/unified_push_registration_store.dart';

import '../../helpers/fake_matrix.dart';

class _FakeUnifiedPush extends UnifiedPushPlatform {
  List<String> installed = const [];
  String? ackDistributor;
  String? defaultDistributor;
  final saved = <String>[];
  void Function(PushEndpoint endpoint, String instance)? onNewEndpoint;
  void Function(FailedReason reason, String instance)? onRegistrationFailed;

  @override
  Future<List<String>> getDistributors(List<String> features) async =>
      installed;

  @override
  Future<String?> getDistributor() async => ackDistributor;

  @override
  Future<void> saveDistributor(String distributor) async {
    saved.add(distributor);
  }

  int registerCalls = 0;

  @override
  Future<void> register(
    String instance,
    List<String> features,
    String? messageForDistributor,
    String? vapid,
  ) async {
    registerCalls++;
  }

  @override
  Future<bool> tryUseCurrentOrDefaultDistributor() async {
    final chosen = defaultDistributor;
    if (chosen == null) return false;
    ackDistributor = chosen;
    return true;
  }

  int unregisterCalls = 0;

  @override
  Future<void> unregister(String instance) async {
    unregisterCalls++;
  }

  @override
  Future<void> initializeCallback({
    void Function(PushEndpoint endpoint, String instance)? onNewEndpoint,
    void Function(FailedReason reason, String instance)? onRegistrationFailed,
    void Function(String instance)? onUnregistered,
    void Function(PushMessage message, String instance)? onMessage,
  }) async {
    this.onNewEndpoint = onNewEndpoint;
    this.onRegistrationFailed = onRegistrationFailed;
  }

  @override
  Future<void> initializeOnTempUnavailable(
    void Function(String instance)? onTempUnavailable,
  ) async => throw UnimplementedError();

  @override
  void setLinuxOptions(LinuxOptions options) {}
}

void main() {
  late _FakeUnifiedPush fake;
  late UnifiedPushDeliveryProvider provider;

  setUp(() {
    fake = _FakeUnifiedPush();
    UnifiedPushPlatform.instance = fake;
    provider = UnifiedPushDeliveryProvider()
      ..distributorIgnoresBatteryOptimizations = ((_) async => true)
      ..gatewayHttpClient = (() =>
          MockClient((_) async => http.Response('not found', 404)));
  });

  test(
    'a system-default distributor wins over the first installed one',
    () async {
      fake.installed = ['io.heckel.ntfy', 'org.unifiedpush.distributor.sunup'];
      fake.defaultDistributor = 'org.unifiedpush.distributor.sunup';

      await provider.discoverDistributors();

      expect(provider.status.value, UnifiedPushStatus.distributorSelected);
      expect(provider.savedDistributor, 'org.unifiedpush.distributor.sunup');
      expect(fake.saved, isEmpty, reason: 'the platform already saved it');
    },
  );

  test('one distributor installed is picked without asking', () async {
    fake.installed = ['io.heckel.ntfy'];

    await provider.discoverDistributors();

    expect(provider.status.value, UnifiedPushStatus.distributorSelected);
    expect(provider.savedDistributor, 'io.heckel.ntfy');
    expect(fake.saved, ['io.heckel.ntfy']);
  });

  test('no distributor installed reports that, and saves nothing', () async {
    fake.installed = const [];

    await provider.discoverDistributors();

    expect(provider.status.value, UnifiedPushStatus.noDistributorFound);
    expect(provider.savedDistributor, isNull);
    expect(fake.saved, isEmpty);
  });

  test('several installed takes the first rather than asking', () async {
    fake.installed = [
      'io.heckel.ntfy',
      'org.unifiedpush.distributor.sunup',
      'org.unifiedpush.distributor.nextpush',
    ];

    await provider.discoverDistributors();

    expect(provider.status.value, UnifiedPushStatus.distributorSelected);
    expect(provider.savedDistributor, 'io.heckel.ntfy');
    expect(fake.saved, ['io.heckel.ntfy']);
  });

  test('re-scans even when one is already saved and acknowledged', () async {
    fake.ackDistributor = 'org.unifiedpush.distributor.sunup';
    fake.installed = ['io.heckel.ntfy'];

    await provider.discoverDistributors();

    expect(provider.status.value, UnifiedPushStatus.distributorSelected);
    expect(provider.savedDistributor, 'io.heckel.ntfy');
    expect(fake.saved, ['io.heckel.ntfy']);
  });

  test(
    'knownDistributor falls back to the saved pick before it is acknowledged',
    () async {
      fake.installed = ['io.heckel.ntfy'];
      await provider.discoverDistributors();

      expect(await fake.getDistributor(), isNull);
      expect(await provider.knownDistributor(), 'io.heckel.ntfy');
    },
  );

  group('start() auto-registration', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test(
      'registers by itself when exactly one distributor is installed',
      () async {
        fake.installed = ['io.heckel.ntfy'];

        await provider.start(buildTestClient());

        expect(fake.saved, ['io.heckel.ntfy']);
        expect(fake.registerCalls, 1);
        expect(provider.status.value, UnifiedPushStatus.registering);
      },
    );

    test(
      'registers with the first distributor when several are installed',
      () async {
        fake.installed = [
          'io.heckel.ntfy',
          'org.unifiedpush.distributor.sunup',
        ];

        await provider.start(buildTestClient());

        expect(provider.status.value, UnifiedPushStatus.registering);
        expect(fake.saved, ['io.heckel.ntfy']);
        expect(fake.registerCalls, 1);
      },
    );

    test('registers nothing when no distributor is installed', () async {
      fake.installed = const [];

      await provider.start(buildTestClient());

      expect(provider.status.value, UnifiedPushStatus.noDistributorFound);
      expect(fake.registerCalls, 0);
    });

    test('does not register again on a repeated start()', () async {
      fake.installed = ['io.heckel.ntfy'];

      await provider.start(buildTestClient());
      await provider.start(buildTestClient());
      await provider.start(buildTestClient());

      expect(fake.registerCalls, 1);
    });

    test('uses an already-acknowledged pick instead of re-asking', () async {
      fake.installed = ['io.heckel.ntfy', 'org.unifiedpush.distributor.sunup'];
      fake.ackDistributor = 'io.heckel.ntfy';

      await provider.start(buildTestClient());

      expect(provider.status.value, UnifiedPushStatus.registering);
      expect(provider.savedDistributor, 'io.heckel.ntfy');
      expect(fake.registerCalls, 1);
    });
  });

  group('restore reconciliation', () {
    ({dynamic client, List<String> pusherPosts}) reconcilingClient({
      List<Map<String, Object?>>? onServer,
    }) {
      final posts = <String>[];
      final c = buildTestClient(
        userId: '@me:example.org',
        deviceId: 'TESTDEVICE',
        httpClient: MockClient((request) async {
          if (request.url.path.contains('pushers/set')) {
            posts.add(request.body);
            return http.Response('{}', 200);
          }
          if (request.url.path.endsWith('/pushers')) {
            if (onServer == null) {
              return http.Response('{"errcode":"M_UNKNOWN"}', 500);
            }
            return http.Response(jsonEncode({'pushers': onServer}), 200);
          }
          return http.Response('{}', 200);
        }),
      );
      c.baseUri = Uri.parse('https://example.org');
      c.bearerToken = 'test-token';
      return (client: c, pusherPosts: posts);
    }

    Map<String, Object?> serverPusher(String pushkey) => {
      'app_id': unifiedPushAppId,
      'pushkey': pushkey,
      'app_display_name': 'Zuno Chat',
      'device_display_name': 'Phone',
      'kind': 'http',
      'lang': 'en',
    };

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await saveUnifiedPushRegistration(
        await SharedPreferences.getInstance(),
        endpointUrl: Uri.parse('https://ntfy.sh/abc123'),
        gatewayUrl: Uri.parse('https://ntfy.sh/_matrix/push/v1/notify'),
      );
    });

    test('re-posts when the homeserver has dropped the pusher', () async {
      final env = reconcilingClient(
        onServer: [serverPusher('https://ntfy.sh/somebody-else')],
      );

      await provider.start(env.client);

      expect(env.pusherPosts, hasLength(1));
      expect(env.pusherPosts.single, contains('https://ntfy.sh/abc123'));
      expect(provider.status.value, UnifiedPushStatus.ready);
    });

    test('leaves a live registration alone', () async {
      final env = reconcilingClient(
        onServer: [serverPusher('https://ntfy.sh/abc123')],
      );

      await provider.start(env.client);

      expect(env.pusherPosts, isEmpty);
      expect(provider.status.value, UnifiedPushStatus.ready);
    });

    test('does not re-post when the pusher list cannot be read', () async {
      final env = reconcilingClient(onServer: null);

      await provider.start(env.client);

      expect(env.pusherPosts, isEmpty);
      expect(provider.status.value, UnifiedPushStatus.ready);
    });
  });

  group('stop()', () {
    ({dynamic client, List<String> pusherPosts}) pusherClient({
      bool failDelete = false,
    }) {
      final posts = <String>[];
      final c = buildTestClient(
        userId: '@me:example.org',
        deviceId: 'TESTDEVICE',
        httpClient: MockClient((request) async {
          if (request.url.path.contains('pushers/set')) {
            posts.add(request.body);
            if (failDelete) {
              return http.Response('{"errcode":"M_FORBIDDEN"}', 403);
            }
          }
          return http.Response('{}', 200);
        }),
      );
      c.baseUri = Uri.parse('https://example.org');
      c.bearerToken = 'test-token';
      return (client: c, pusherPosts: posts);
    }

    Future<void> persistRegistration() async {
      await saveUnifiedPushRegistration(
        await SharedPreferences.getInstance(),
        endpointUrl: Uri.parse('https://ntfy.sh/abc123'),
        gatewayUrl: Uri.parse('https://ntfy.sh/_matrix/push/v1/notify'),
      );
    }

    test('does nothing when there is nothing registered', () async {
      SharedPreferences.setMockInitialValues({});
      final env = pusherClient();

      await provider.stop(env.client);

      expect(env.pusherPosts, isEmpty);
      expect(fake.unregisterCalls, 0);
    });

    test('tears down a registration persisted by an earlier process, '
        'even though start() never ran in this one', () async {
      SharedPreferences.setMockInitialValues({});
      await persistRegistration();
      final env = pusherClient();

      await provider.stop(env.client);

      expect(env.pusherPosts, hasLength(1), reason: 'pusher should be deleted');
      expect(env.pusherPosts.single, contains('ntfy.sh/abc123'));
      expect(
        fake.unregisterCalls,
        1,
        reason: 'distributor should be unregistered',
      );
      expect(
        readUnifiedPushRegistration(await SharedPreferences.getInstance()),
        isNull,
        reason: 'persisted registration should be cleared',
      );
      expect(provider.status.value, UnifiedPushStatus.idle);
    });

    test('deletes the pusher by setting kind: null', () async {
      SharedPreferences.setMockInitialValues({});
      await persistRegistration();
      final env = pusherClient();

      await provider.stop(env.client);

      expect(env.pusherPosts.single, contains('"kind":null'));
    });

    test('surfaces a failed pusher delete instead of swallowing it', () async {
      SharedPreferences.setMockInitialValues({});
      await persistRegistration();
      final env = pusherClient(failDelete: true);

      await provider.stop(env.client);

      expect(provider.lastPusherError, isNotNull);
      expect(fake.unregisterCalls, 1);
      expect(
        readUnifiedPushRegistration(await SharedPreferences.getInstance()),
        isNull,
      );
    });

    test('a second stop is a no-op once everything is torn down', () async {
      SharedPreferences.setMockInitialValues({});
      await persistRegistration();
      final env = pusherClient();

      await provider.stop(env.client);
      await provider.stop(env.client);

      expect(env.pusherPosts, hasLength(1));
      expect(fake.unregisterCalls, 1);
    });
  });

  ({Client client, List<String> pusherPosts}) postingClient({
    bool Function()? failPost,
  }) {
    final posts = <String>[];
    final c = buildTestClient(
      userId: '@me:example.org',
      deviceId: 'TESTDEVICE',
      httpClient: MockClient((request) async {
        if (request.url.path.contains('pushers/set')) {
          if (failPost?.call() ?? false) {
            return http.Response('{"errcode":"M_UNKNOWN"}', 500);
          }
          posts.add(request.body);
          return http.Response('{}', 200);
        }
        if (request.url.path.endsWith('/pushers')) {
          return http.Response('{"pushers":[]}', 200);
        }
        return http.Response('{}', 200);
      }),
    );
    c.baseUri = Uri.parse('https://example.org');
    c.bearerToken = 'test-token';
    c.homeserver = Uri.parse('https://matrix.example.org');
    return (client: c, pusherPosts: posts);
  }

  group('retry after a transient failure', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider.retryDelay = (attempt) =>
          attempt < 3 ? Duration.zero : const Duration(days: 1);
    });

    test('a distributor that refused to register is asked again', () async {
      fake.installed = ['io.heckel.ntfy'];
      await provider.start(buildTestClient());
      expect(fake.registerCalls, 1);

      fake.onRegistrationFailed!(FailedReason.network, 'default');
      expect(provider.status.value, UnifiedPushStatus.registrationFailed);
      expect(provider.retryScheduled, isTrue);
      await pumpEventQueue();

      expect(fake.registerCalls, greaterThan(1));
    });

    test('a distributor needing user action is not nagged', () async {
      fake.installed = ['io.heckel.ntfy'];
      await provider.start(buildTestClient());

      fake.onRegistrationFailed!(FailedReason.actionRequired, 'default');

      expect(provider.retryScheduled, isFalse);
    });

    test('a pusher the homeserver rejected is re-posted by itself', () async {
      var attempts = 0;
      final env = postingClient(failPost: () => ++attempts == 1);
      fake.installed = ['io.heckel.ntfy'];
      await provider.start(env.client);

      fake.onNewEndpoint!(PushEndpoint('https://ntfy.sh/abc', null), 'default');
      await pumpEventQueue();

      expect(attempts, 2);
      expect(provider.status.value, UnifiedPushStatus.ready);
      expect(env.pusherPosts, hasLength(1));
    });

    test('stop cancels a pending retry', () async {
      provider.retryDelay = (_) => const Duration(days: 1);
      fake.installed = ['io.heckel.ntfy'];
      await provider.start(buildTestClient());
      fake.onRegistrationFailed!(FailedReason.network, 'default');
      expect(provider.retryScheduled, isTrue);

      await provider.stop(buildTestClient());

      expect(provider.retryScheduled, isFalse);
    });
  });

  group('recheckRegistration on resume', () {
    var now = DateTime(2031, 1, 1, 9);

    setUp(() async {
      now = DateTime(2031, 1, 1, 9);
      provider.now = () => now;
      SharedPreferences.setMockInitialValues({});
      await saveUnifiedPushRegistration(
        await SharedPreferences.getInstance(),
        endpointUrl: Uri.parse('https://ntfy.sh/abc123'),
        gatewayUrl: Uri.parse('https://ntfy.sh/_matrix/push/v1/notify'),
      );
    });

    test('re-posts a pusher the homeserver has since dropped', () async {
      final env = postingClient();
      fake.ackDistributor = 'io.heckel.ntfy';
      await provider.start(env.client);
      expect(provider.status.value, UnifiedPushStatus.ready);
      final before = env.pusherPosts.length;
      now = now.add(registrationRecheckInterval);

      await provider.recheckRegistration(env.client);

      expect(env.pusherPosts.length, before + 1);
    });

    test('does not ask again within the interval', () async {
      final env = postingClient();
      fake.ackDistributor = 'io.heckel.ntfy';
      await provider.start(env.client);
      final before = env.pusherPosts.length;
      now = now.add(const Duration(minutes: 5));

      await provider.recheckRegistration(env.client);

      expect(env.pusherPosts.length, before);
    });
  });

  group('distributor battery restriction', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('is flagged when the distributor is not exempt', () async {
      provider.distributorIgnoresBatteryOptimizations = (_) async => false;
      fake.installed = ['io.heckel.ntfy'];

      await provider.start(buildTestClient());

      expect(provider.distributorBatteryRestricted.value, isTrue);
    });

    test('is clear when the distributor is exempt', () async {
      provider.distributorIgnoresBatteryOptimizations = (_) async => true;
      fake.installed = ['io.heckel.ntfy'];

      await provider.start(buildTestClient());

      expect(provider.distributorBatteryRestricted.value, isFalse);
    });

    test('asks about the distributor that was actually chosen', () async {
      String? asked;
      provider.distributorIgnoresBatteryOptimizations = (pkg) async {
        asked = pkg;
        return true;
      };
      fake.installed = ['org.unifiedpush.distributor.sunup'];

      await provider.start(buildTestClient());

      expect(asked, 'org.unifiedpush.distributor.sunup');
    });
  });

  group('WebPush pusher through the homeserver gateway', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    tearDown(() => unifiedPushViaHomeserverGateway = false);

    test('registers the key set with the homeserver\'s own gateway when '
        'enabled', () async {
      unifiedPushViaHomeserverGateway = true;
      final env = postingClient();
      fake.installed = ['io.heckel.ntfy'];
      await provider.start(env.client);

      fake.onNewEndpoint!(
        PushEndpoint('https://ntfy.sh/abc', PublicKeySet('P256KEY', 'AUTH')),
        'default',
      );
      await pumpEventQueue();

      final body = jsonDecode(env.pusherPosts.single) as Map;
      expect(body['pushkey'], 'P256KEY');
      final data = body['data'] as Map;
      expect(data['url'], 'https://matrix.example.org/_matrix/push/v1/notify');
      expect(data['endpoint'], 'https://ntfy.sh/abc');
      expect(data['auth'], 'AUTH');
      expect(data['format'], 'event_id_only');
      final stored = readUnifiedPushRegistration(
        await SharedPreferences.getInstance(),
      );
      expect(stored?.pushkey, 'P256KEY');
    });

    test('falls back to the discovered gateway without a key set', () async {
      unifiedPushViaHomeserverGateway = true;
      final env = postingClient();
      fake.installed = ['io.heckel.ntfy'];
      await provider.start(env.client);

      fake.onNewEndpoint!(PushEndpoint('https://ntfy.sh/abc', null), 'default');
      await pumpEventQueue();

      final body = jsonDecode(env.pusherPosts.single) as Map;
      expect(body['pushkey'], 'https://ntfy.sh/abc');
    });

    test('is off by default, so keys are ignored', () async {
      final env = postingClient();
      fake.installed = ['io.heckel.ntfy'];
      await provider.start(env.client);

      fake.onNewEndpoint!(
        PushEndpoint('https://ntfy.sh/abc', PublicKeySet('P256KEY', 'AUTH')),
        'default',
      );
      await pumpEventQueue();

      final body = jsonDecode(env.pusherPosts.single) as Map;
      expect(body['pushkey'], 'https://ntfy.sh/abc');
    });
  });
}
