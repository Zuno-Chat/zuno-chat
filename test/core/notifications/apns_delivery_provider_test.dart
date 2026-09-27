import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/apns_delivery_provider.dart';

import '../../helpers/fake_matrix.dart';
import '../../helpers/platform_capabilities.dart';

class _RecordingClient extends Client {
  _RecordingClient() : super('test', database: FakeDatabaseApi()) {
    homeserver = Uri.parse('https://matrix.example.org');
  }

  final posted = <Pusher>[];
  final deleted = <PusherId>[];
  Object? postError;

  @override
  Future<void> postPusher(Pusher pusher, {bool? append}) async {
    if (postError != null) throw postError!;
    posted.add(pusher);
  }

  @override
  Future<void> deletePusher(PusherId pusherId) async {
    deleted.add(pusherId);
  }

  List<Map<String, Object?>>? pushersOnServer;

  @override
  Future<Map<String, Object?>> request(
    RequestType type,
    String action, {
    dynamic data = '',
    String contentType = 'application/json',
    Map<String, Object?>? query,
  }) async {
    if (action != '/client/v3/pushers') {
      return super.request(type, action, data: data, query: query);
    }
    final pushers = pushersOnServer;
    if (pushers == null) throw Exception('offline');
    return {'pushers': pushers};
  }
}

Map<String, Object?> _serverPusher(String pushkey) => {
  'app_id': 'im.zuno.chat.ios',
  'pushkey': pushkey,
  'app_display_name': 'Zuno',
  'device_display_name': 'Zuno on iOS',
  'kind': 'http',
  'lang': 'en',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApnsDeliveryProvider provider;
  late _RecordingClient client;
  late int tokenReads;
  String? deviceToken;

  ApnsDeliveryProvider providerWith({required bool registration}) =>
      ApnsDeliveryProvider(
          capabilities: capabilitiesLike(
            iosCapabilities,
            apnsRegistration: registration,
          ),
        )
        ..tokenReader = () async {
          tokenReads++;
          return deviceToken;
        }
        ..retryDelay = ((_) => const Duration(days: 1));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    client = _RecordingClient();
    tokenReads = 0;
    deviceToken = 'a1b2c3';
    provider = providerWith(registration: true);
  });

  tearDown(() => provider.stop(client));

  test(
    'registers the Apple push token as a pusher and reports ready',
    () async {
      await provider.start(client);

      expect(provider.status.value, ApnsStatus.ready);
      final pusher = client.posted.single;
      expect(pusher.appId, 'im.zuno.chat.ios');
      expect(pusher.pushkey, 'a1b2c3');
      expect(pusher.kind, 'http');
      expect(pusher.data.toJson(), {
        'default_payload': {
          'aps': {
            'mutable-content': 1,
            'alert': {'body': 'New message'},
            'sound': 'default',
          },
        },
        'format': 'event_id_only',
        'url': 'https://matrix.example.org/_matrix/push/v1/notify',
      });
    },
  );

  test('without the native token handler it stays idle and never asks for a '
      'token', () async {
    provider = providerWith(registration: false);

    await provider.start(client);
    await provider.registerNow(client);

    expect(provider.status.value, ApnsStatus.idle);
    expect(tokenReads, 0);
    expect(client.posted, isEmpty);
  });

  test('is idempotent across repeated start() calls', () async {
    await provider.start(client);
    await provider.start(client);

    expect(client.posted, hasLength(1));
  });

  test(
    'a token that cannot be read reports tokenFailed and schedules a retry',
    () async {
      provider.tokenReader = () async => throw Exception('no aps-environment');

      await provider.start(client);

      expect(provider.status.value, ApnsStatus.tokenFailed);
      expect(provider.retryScheduled, isTrue);
      expect(client.posted, isEmpty);
    },
  );

  test('a pusher the server rejects reports pusherFailed with its error, and '
      'retrying after a fix registers', () async {
    client.postError = Exception('M_UNKNOWN');

    await provider.start(client);

    expect(provider.status.value, ApnsStatus.pusherFailed);
    expect(provider.lastPusherError, contains('M_UNKNOWN'));
    expect(provider.retryScheduled, isTrue);

    client.postError = null;
    await provider.retryIfFailed(client);

    expect(provider.status.value, ApnsStatus.ready);
    expect(provider.lastPusherError, isNull);
  });

  test(
    'a relaunch with the same token and a live pusher posts nothing',
    () async {
      await provider.start(client);
      client.posted.clear();
      client.pushersOnServer = [_serverPusher('a1b2c3')];

      final relaunched = providerWith(registration: true);
      await relaunched.start(client);

      expect(relaunched.status.value, ApnsStatus.ready);
      expect(relaunched.token, 'a1b2c3');
      expect(client.posted, isEmpty);
    },
  );

  test('a relaunch with a new token registers it', () async {
    await provider.start(client);
    client.posted.clear();
    deviceToken = 'd4e5f6';

    final relaunched = providerWith(registration: true);
    await relaunched.start(client);

    expect(client.posted.single.pushkey, 'd4e5f6');
    expect(relaunched.token, 'd4e5f6');
  });

  test(
    'a relaunch whose pusher is gone from the server posts it again',
    () async {
      await provider.start(client);
      client.posted.clear();
      client.pushersOnServer = [];

      final relaunched = providerWith(registration: true);
      await relaunched.start(client);

      expect(client.posted.single.pushkey, 'a1b2c3');
    },
  );

  test('stop removes the pusher and forgets the token', () async {
    await provider.start(client);

    await provider.stop(client);

    expect(client.deleted.single.appId, 'im.zuno.chat.ios');
    expect(client.deleted.single.pushkey, 'a1b2c3');
    expect(provider.status.value, ApnsStatus.idle);
    expect(provider.token, isNull);

    final relaunched = providerWith(registration: true);
    deviceToken = null;
    await relaunched.start(client);
    expect(relaunched.token, isNull);
  });

  test('stop with nothing registered touches neither the server nor the '
      'token handler, as on Android', () async {
    provider = providerWith(registration: false);

    await provider.stop(client);

    expect(client.deleted, isEmpty);
    expect(tokenReads, 0);
  });
}
