import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/apns_delivery_provider.dart';
import 'package:zuno/core/push/apns_pusher.dart';
import 'package:zuno/core/push/registration_retry.dart';

import '../../helpers/fake_matrix.dart';
import '../../helpers/platform_capabilities.dart';

const _token =
    'a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4';
const _pushkey = 'obLD1KGyw9ShssPUobLD1KGyw9ShssPUobLD1KGyw9Q=';
const _newToken =
    'd4e5f6a7d4e5f6a7d4e5f6a7d4e5f6a7d4e5f6a7d4e5f6a7d4e5f6a7d4e5f6a7';
const _newPushkey = '1OX2p9Tl9qfU5fan1OX2p9Tl9qfU5fan1OX2p9Tl9qc=';

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

Map<String, Object?> _serverPusher(String pushkey, {String? appId}) => {
  'app_id': appId ?? apnsAppId,
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
  late DateTime now;
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
        ..retryDelay = ((_) => const Duration(days: 1))
        ..now = (() => now);

  Future<void> recheckAfterInterval() async {
    now = now.add(registrationRecheckInterval);
    await provider.recheckRegistration(client);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    client = _RecordingClient();
    tokenReads = 0;
    deviceToken = _token;
    now = DateTime(2026, 9, 27, 12);
    provider = providerWith(registration: true);
  });

  tearDown(() => provider.stop(client));

  test(
    'registers the Apple push token as a pusher and reports ready',
    () async {
      await provider.start(client);

      expect(provider.status.value, ApnsStatus.ready);
      final pusher = client.posted.single;
      expect(pusher.appId, apnsAppId);
      expect(pusher.pushkey, _pushkey);
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
      expect(provider.token, _token);
      expect(provider.pushkey, _pushkey);
    },
  );

  test(
    'a token that is not hex is refused before the server sees it',
    () async {
      deviceToken = 'apns-token';

      await provider.start(client);

      expect(provider.status.value, ApnsStatus.tokenFailed);
      expect(client.posted, isEmpty);
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
      client.pushersOnServer = [_serverPusher(_pushkey)];

      final relaunched = providerWith(registration: true);
      await relaunched.start(client);

      expect(relaunched.status.value, ApnsStatus.ready);
      expect(relaunched.token, _token);
      expect(relaunched.pushkey, _pushkey);
      expect(client.posted, isEmpty);
      expect(relaunched.dropped.value, 0);
    },
  );

  test('a relaunch with a new token registers it and removes the old '
      'pusher', () async {
    await provider.start(client);
    client.posted.clear();
    deviceToken = _newToken;

    final relaunched = providerWith(registration: true);
    await relaunched.start(client);

    expect(client.posted.single.pushkey, _newPushkey);
    expect(relaunched.token, _newToken);
    expect(client.deleted.single.appId, apnsAppId);
    expect(client.deleted.single.pushkey, _pushkey);
    expect(relaunched.dropped.value, 0);
  });

  test('a release build replacing a development one moves the pusher to the '
      'production app id', () async {
    provider.appId = apnsDevelopmentAppId;
    await provider.start(client);
    client.posted.clear();
    client.pushersOnServer = [
      _serverPusher(_pushkey, appId: apnsDevelopmentAppId),
    ];

    final relaunched = providerWith(registration: true)
      ..appId = apnsProductionAppId;
    await relaunched.start(client);

    expect(client.posted.single.appId, apnsProductionAppId);
    expect(client.posted.single.pushkey, _pushkey);
    expect(client.deleted.single.appId, apnsDevelopmentAppId);
    expect(client.deleted.single.pushkey, _pushkey);
    expect(relaunched.dropped.value, 0);
  });

  test('a relaunch whose pusher is gone from the server posts it again and '
      'counts the drop', () async {
    await provider.start(client);
    client.posted.clear();
    client.pushersOnServer = [];

    final relaunched = providerWith(registration: true);
    await relaunched.start(client);

    expect(client.posted.single.pushkey, _pushkey);
    expect(relaunched.status.value, ApnsStatus.ready);
    expect(relaunched.dropped.value, 1);
  });

  test('every recheck that finds the pusher gone adds to the count, and the '
      'count survives a relaunch', () async {
    await provider.start(client);
    client.pushersOnServer = [];

    await recheckAfterInterval();
    await recheckAfterInterval();

    expect(provider.dropped.value, 2);
    expect(client.posted, hasLength(3));
    expect(client.deleted, isEmpty);

    client.pushersOnServer = [_serverPusher(_pushkey)];
    final relaunched = providerWith(registration: true);
    await relaunched.start(client);

    expect(relaunched.dropped.value, 2);
  });

  test('registering from Settings starts the count over', () async {
    await provider.start(client);
    client.pushersOnServer = [];
    await recheckAfterInterval();
    expect(provider.dropped.value, 1);

    await provider.registerNow(client);

    expect(provider.dropped.value, 0);
    expect(provider.status.value, ApnsStatus.ready);
  });

  test('stop removes the pusher and forgets the token and the count', () async {
    await provider.start(client);
    client.pushersOnServer = [];
    await recheckAfterInterval();

    await provider.stop(client);

    expect(client.deleted.single.appId, apnsAppId);
    expect(client.deleted.single.pushkey, _pushkey);
    expect(provider.status.value, ApnsStatus.idle);
    expect(provider.token, isNull);
    expect(provider.dropped.value, 0);

    final relaunched = providerWith(registration: true);
    deviceToken = null;
    await relaunched.start(client);
    expect(relaunched.token, isNull);
    expect(relaunched.dropped.value, 0);
  });

  test('stop with nothing registered touches neither the server nor the '
      'token handler, as on Android', () async {
    provider = providerWith(registration: false);

    await provider.stop(client);

    expect(client.deleted, isEmpty);
    expect(tokenReads, 0);
  });
}
