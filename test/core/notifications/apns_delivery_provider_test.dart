import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/apns_delivery_provider.dart';
import 'package:zuno/core/notifications/notification_sound_settings.dart';
import 'package:zuno/core/push/apns_pusher.dart';
import 'package:zuno/core/push/registration_retry.dart';

import '../../helpers/caught_reports.dart';
import '../../helpers/fake_permissions.dart';
import '../../helpers/platform_capabilities.dart';
import '../../helpers/pusher_recording_client.dart';

const _token =
    'a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4';
const _pushkey = 'obLD1KGyw9ShssPUobLD1KGyw9ShssPUobLD1KGyw9Q=';
const _newToken =
    'd4e5f6a7d4e5f6a7d4e5f6a7d4e5f6a7d4e5f6a7d4e5f6a7d4e5f6a7d4e5f6a7';
const _newPushkey = '1OX2p9Tl9qfU5fan1OX2p9Tl9qfU5fan1OX2p9Tl9qc=';

Map<String, Object?> _serverPusher(
  String pushkey, {
  String? appId,
  String url = 'https://matrix.example.org/_matrix/push/v1/notify',
  String format = 'event_id_only',
}) => serverPusherJson(
  appId: appId ?? apnsAppId,
  pushkey: pushkey,
  appName: 'Zuno',
  deviceName: 'Zuno on iOS',
  data: {'url': url, 'format': format},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApnsDeliveryProvider provider;
  late PusherRecordingClient client;
  late int tokenReads;
  late int environmentReads;
  late DateTime now;
  String? deviceToken;
  late Future<String?> Function() readEnvironment;

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
        ..environmentReader = () {
          environmentReads++;
          return readEnvironment();
        }
        ..retryDelay = ((_) => const Duration(days: 1))
        ..now = (() => now);

  Future<void> recheckAfterInterval() async {
    now = now.add(registrationRecheckInterval);
    await provider.recheckRegistration(client);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    client = PusherRecordingClient();
    tokenReads = 0;
    environmentReads = 0;
    readEnvironment = () async => 'development';
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
            'sound': 'message_tone.caf',
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

  group('a token Apple does not give', () {
    setUp(installFakePermissions);

    test('in time, as while offline, is retried without a report', () async {
      provider.tokenReader = () async =>
          throw PlatformException(code: 'timeout');

      expect(await reportsDuring(() => provider.start(client)), isEmpty);
      expect(provider.status.value, ApnsStatus.tokenFailed);
      expect(provider.retryScheduled, isTrue);
    });

    test('because registering failed is reported, and retried', () async {
      provider.tokenReader = () async =>
          throw PlatformException(code: 'registration_failed');

      expect(await reportsDuring(() => provider.start(client)), [
        'apns token request',
      ]);
      expect(provider.retryScheduled, isTrue);
    });

    test('in time on a relaunch keeps the registration without a '
        'report', () async {
      await provider.start(client);
      final relaunched = providerWith(registration: true)
        ..tokenReader = () async => throw PlatformException(code: 'timeout');

      expect(await reportsDuring(() => relaunched.start(client)), isEmpty);
      expect(relaunched.status.value, ApnsStatus.ready);
    });

    test('on a relaunch for any other reason is reported', () async {
      await provider.start(client);
      final relaunched = providerWith(registration: true)
        ..tokenReader = () async =>
            throw PlatformException(code: 'registration_failed');

      expect(await reportsDuring(() => relaunched.start(client)), [
        'apns token check',
      ]);
    });
  });

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

  test('with no server to send through yet, registering is tried again '
      'later', () async {
    client.homeserver = null;

    await provider.start(client);

    expect(provider.status.value, ApnsStatus.pusherFailed);
    expect(provider.retryScheduled, isTrue);
    expect(client.posted, isEmpty);
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

  group('the push environment of this build', () {
    test('production registers under the production app id, whatever the '
        'build mode', () async {
      readEnvironment = () async => 'production';

      await provider.start(client);

      expect(client.posted.single.appId, apnsProductionAppId);
    });

    test('a relaunch under another environment moves the pusher to its app '
        'id', () async {
      await provider.start(client);
      client.posted.clear();
      client.pushersOnServer = [
        _serverPusher(_pushkey, appId: apnsDevelopmentAppId),
      ];
      readEnvironment = () async => 'production';

      final relaunched = providerWith(registration: true);
      await relaunched.start(client);

      expect(client.posted.single.appId, apnsProductionAppId);
      expect(client.posted.single.pushkey, _pushkey);
      expect(client.deleted.single.appId, apnsDevelopmentAppId);
      expect(client.deleted.single.pushkey, _pushkey);
      expect(relaunched.dropped.value, 0);
    });

    test('without Apple push registration the environment is never '
        'asked', () async {
      final unregistered = providerWith(registration: false);

      expect(await unregistered.currentAppId(), apnsAppId);
      expect(environmentReads, 0);
    });

    test('is read once per launch', () async {
      await provider.start(client);
      await provider.registerNow(client);

      expect(environmentReads, 1);
    });

    test('is read again after a reset', () async {
      await provider.start(client);
      readEnvironment = () async => 'production';

      provider.resetEnvironmentForTesting();

      expect(await provider.currentAppId(), apnsProductionAppId);
      expect(environmentReads, 2);
    });

    group('falling back to the build mode', () {
      late List<String> lines;

      setUp(() {
        installFakePermissions();
        lines = recordDebugPrints();
      });

      test('an unreadable environment falls back to the build mode and is '
          'asked again next time', () async {
        readEnvironment = () async => throw MissingPluginException();

        await provider.start(client);

        expect(client.posted.single.appId, apnsAppId);
        expect(
          lines.single,
          allOf(
            startsWith('zuno/caught: apns environment read:'),
            contains('MissingPluginException'),
          ),
        );

        readEnvironment = () async => 'production';
        await provider.registerNow(client);

        expect(client.posted.last.appId, apnsProductionAppId);
        expect(client.deleted.single.appId, apnsAppId);
      });

      test('an environment name it does not know falls back to the build '
          'mode, names it in the log and is asked again next time', () async {
        readEnvironment = () async => 'staging';

        await provider.start(client);

        expect(client.posted.single.appId, apnsAppId);
        expect(
          lines.single,
          allOf(contains('unknown APNs environment'), contains('staging')),
        );

        readEnvironment = () async => 'production';
        await provider.registerNow(client);

        expect(client.posted.last.appId, apnsProductionAppId);
        expect(environmentReads, 2);
      });
    });
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

  group('a pusher the homeserver still holds', () {
    test('exactly as this app posted it is left alone', () async {
      await provider.start(client);
      client.pushersOnServer = [client.posted.single.toJson()];
      client.posted.clear();

      await recheckAfterInterval();

      expect(client.posted, isEmpty);
      expect(provider.dropped.value, 0);
      expect(provider.status.value, ApnsStatus.ready);
    });

    test('pointing at an old address is posted again to this server without '
        'counting a drop', () async {
      await provider.start(client);
      client.posted.clear();
      client.pushersOnServer = [
        _serverPusher(
          _pushkey,
          url: 'https://old.example.org/_matrix/push/v1/notify',
        ),
      ];

      final relaunched = providerWith(registration: true);
      await relaunched.start(client);

      final pusher = client.posted.single;
      expect(pusher.appId, apnsAppId);
      expect(pusher.pushkey, _pushkey);
      expect(
        pusher.data.url.toString(),
        'https://matrix.example.org/_matrix/push/v1/notify',
      );
      expect(relaunched.dropped.value, 0);
      expect(relaunched.status.value, ApnsStatus.ready);
      expect(client.deleted, isEmpty);
    });

    test(
      'asking for full events is posted again with event ids only',
      () async {
        await provider.start(client);
        client.posted.clear();
        client.pushersOnServer = [_serverPusher(_pushkey, format: 'full')];

        await recheckAfterInterval();

        expect(client.posted.single.data.format, 'event_id_only');
        expect(provider.dropped.value, 0);
      },
    );

    test('at the same address in another spelling is left alone', () async {
      await provider.start(client);
      client.posted.clear();
      client.pushersOnServer = [
        _serverPusher(
          _pushkey,
          url: 'https://Matrix.Example.org:443/_matrix/push/v1/notify',
        ),
      ];

      await recheckAfterInterval();
      final relaunched = providerWith(registration: true);
      await relaunched.start(client);

      expect(client.posted, isEmpty);
    });

    test('posted again but refused, reports the failure and retries', () async {
      await provider.start(client);
      client.pushersOnServer = [
        _serverPusher(
          _pushkey,
          url: 'https://old.example.org/_matrix/push/v1/notify',
        ),
      ];
      client.postError = Exception('M_UNKNOWN');

      await recheckAfterInterval();

      expect(provider.status.value, ApnsStatus.pusherFailed);
      expect(provider.retryScheduled, isTrue);
      expect(provider.dropped.value, 0);
    });

    test('that cannot be listed changes nothing', () async {
      await provider.start(client);
      client.posted.clear();
      client.pushersOnServer = null;

      await recheckAfterInterval();

      expect(client.posted, isEmpty);
      expect(provider.dropped.value, 0);
      expect(provider.status.value, ApnsStatus.ready);
    });
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

  test('stop after the session ended asks the homeserver nothing and shows '
      'no error, since the pusher went with the session', () async {
    await provider.start(client);
    client.signedIn = false;

    await provider.stop(client);

    expect(client.deleted, isEmpty);
    expect(provider.lastPusherError, isNull);
    expect(provider.status.value, ApnsStatus.idle);
  });

  test('stop shows a pusher delete the homeserver refuses', () async {
    await provider.start(client);
    client.deleteError = MatrixException.fromJson({'errcode': 'M_FORBIDDEN'});

    await provider.stop(client);

    expect(provider.lastPusherError, contains('M_FORBIDDEN'));
    expect(provider.status.value, ApnsStatus.idle);
  });

  test('stop with nothing registered touches neither the server nor the '
      'token handler, as on Android', () async {
    provider = providerWith(registration: false);

    await provider.stop(client);

    expect(client.deleted, isEmpty);
    expect(tokenReads, 0);
  });

  group('Message tone', () {
    Object? soundOf(Pusher pusher) =>
        ((pusher.data.toJson()['default_payload'] as Map)['aps']
            as Map)['sound'];

    Future<void> setMessageTone(bool on) async =>
        (await SharedPreferences.getInstance()).setBool(
          messageToneEnabledKey,
          on,
        );

    test('off at registration, the pusher is posted without a sound', () async {
      await setMessageTone(false);

      await provider.start(client);

      expect(provider.status.value, ApnsStatus.ready);
      expect(client.posted.map(soundOf), [null]);
    });

    test('turning it off re-posts the same pusher without a sound', () async {
      await provider.start(client);
      await setMessageTone(false);

      await provider.messageToneChanged(client);

      expect(client.posted.map(soundOf), ['message_tone.caf', null]);
      expect(client.posted.last.appId, apnsAppId);
      expect(client.posted.last.pushkey, _pushkey);
      expect(client.deleted, isEmpty);
      expect(provider.status.value, ApnsStatus.ready);
    });

    test('turning it back on re-posts with the Zuno tone', () async {
      await setMessageTone(false);
      await provider.start(client);
      await setMessageTone(true);

      await provider.messageToneChanged(client);

      expect(client.posted.map(soundOf), [null, 'message_tone.caf']);
    });

    test('a change the pusher already carries posts nothing', () async {
      await provider.start(client);
      await provider.messageToneChanged(client);
      await setMessageTone(false);
      await provider.messageToneChanged(client);

      await provider.messageToneChanged(client);

      expect(client.posted.map(soundOf), ['message_tone.caf', null]);
    });

    test('with nothing registered a change asks for no token and posts '
        'nothing', () async {
      await setMessageTone(false);

      await provider.messageToneChanged(client);

      expect(tokenReads, 0);
      expect(client.posted, isEmpty);
      expect(provider.status.value, ApnsStatus.idle);
    });

    test('a re-post the server rejects leaves the working registration '
        'ready, and the next resume posts the sound again', () async {
      await provider.start(client);
      final reads = tokenReads;
      client.postError = Exception('M_UNKNOWN');
      await setMessageTone(false);

      await provider.messageToneChanged(client);

      expect(provider.status.value, ApnsStatus.ready);
      expect(provider.lastPusherError, isNull);
      expect(provider.retryScheduled, isFalse);
      expect(tokenReads, reads);

      client.postError = null;
      await provider.recheckRegistration(client);

      expect(provider.status.value, ApnsStatus.ready);
      expect(client.posted.map(soundOf), ['message_tone.caf', null]);
      expect(tokenReads, reads);
    });

    test('a sound that already reached the server is not posted again on '
        'resume', () async {
      await provider.start(client);
      await setMessageTone(false);
      await provider.messageToneChanged(client);

      await provider.recheckRegistration(client);

      expect(client.posted.map(soundOf), ['message_tone.caf', null]);
    });

    test('a re-post the server rejects is tried again on the next launch, '
        'too', () async {
      await provider.start(client);
      client.postError = Exception('M_UNKNOWN');
      await setMessageTone(false);
      await provider.messageToneChanged(client);
      client
        ..postError = null
        ..pushersOnServer = [_serverPusher(_pushkey)];

      final relaunched = providerWith(registration: true);
      await relaunched.start(client);

      expect(client.posted.map(soundOf), ['message_tone.caf', null]);
      expect(relaunched.status.value, ApnsStatus.ready);
    });

    test('a change while the pusher is being registered is posted once the '
        'registration lands', () async {
      final hold = client.holdNextPost = Completer<void>();
      final starting = provider.start(client);
      await pumpEventQueue();
      expect(provider.status.value, ApnsStatus.postingPusher);

      await setMessageTone(false);
      await provider.messageToneChanged(client);
      hold.complete();
      await starting;

      expect(client.posted.map(soundOf), ['message_tone.caf', null]);
      expect(provider.status.value, ApnsStatus.ready);
    });

    test('switching back while a re-post is in flight ends on the last '
        'choice', () async {
      await provider.start(client);
      final hold = client.holdNextPost = Completer<void>();
      await setMessageTone(false);
      final first = provider.messageToneChanged(client);
      await pumpEventQueue();

      await setMessageTone(true);
      await provider.messageToneChanged(client);
      hold.complete();
      await first;

      expect(client.posted.map(soundOf), [
        'message_tone.caf',
        null,
        'message_tone.caf',
      ]);
      expect(provider.status.value, ApnsStatus.ready);
    });

    test(
      'a relaunch re-posts a pusher whose sound no longer matches',
      () async {
        await provider.start(client);
        client.posted.clear();
        client.pushersOnServer = [_serverPusher(_pushkey)];
        await setMessageTone(false);

        final relaunched = providerWith(registration: true);
        await relaunched.start(client);

        expect(client.posted.map(soundOf), [null]);
        expect(relaunched.status.value, ApnsStatus.ready);
      },
    );

    test('a relaunch whose pusher already matches posts nothing', () async {
      await setMessageTone(false);
      await provider.start(client);
      client.posted.clear();
      client.pushersOnServer = [_serverPusher(_pushkey)];

      final relaunched = providerWith(registration: true);
      await relaunched.start(client);

      expect(client.posted, isEmpty);
    });

    test('a pusher whose sound was never recorded is re-posted once with the '
        'Zuno tone', () async {
      SharedPreferences.setMockInitialValues({
        'push.apns.token': _token,
        'push.apns.app_id': apnsAppId,
      });
      client.pushersOnServer = [_serverPusher(_pushkey)];

      await provider.start(client);
      final relaunched = providerWith(registration: true);
      await relaunched.start(client);

      expect(client.posted.map(soundOf), ['message_tone.caf']);
      expect(provider.status.value, ApnsStatus.ready);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('push.apns.sound_name'), 'message_tone.caf');
    });

    test('a pusher registered before Message tone reached Apple push is '
        're-posted without a sound when the tone is off', () async {
      SharedPreferences.setMockInitialValues({
        'push.apns.token': _token,
        'push.apns.app_id': apnsAppId,
        messageToneEnabledKey: false,
      });
      client.pushersOnServer = [_serverPusher(_pushkey)];

      await provider.start(client);

      expect(client.posted.map(soundOf), [null]);
      expect(provider.status.value, ApnsStatus.ready);
    });
  });
}
