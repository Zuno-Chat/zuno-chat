import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/delivery/registration_retry.dart';
import 'package:zuno/core/push/fcm/fcm_pusher.dart';
import 'package:zuno/core/push/nse/nse_channel.dart';
import 'package:zuno/core/push/ring/ring_channel.dart';
import 'package:zuno/core/push/ring/ring_registration.dart';
import 'package:zuno/core/push/ring/ring_server.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_permissions.dart';
import '../../../helpers/fake_ring_registration.dart';
import '../../../helpers/platform_capabilities.dart';

class _FakeServer implements RingServer {
  final puts = <Map<String, Object>>[];
  var deleteVoips = 0;
  var deleteDevices = 0;
  Object? deleteDeviceError;
  RingServerReply Function(int kid) reply = (kid) =>
      RingServerAccepted(serverTs: 1790000000000, kid: kid);

  @override
  Future<RingServerReply> putVoip({
    required String appId,
    required String pushkey,
    required int kid,
    required String key,
  }) async {
    puts.add({'appId': appId, 'pushkey': pushkey, 'kid': kid, 'key': key});
    return reply(kid);
  }

  @override
  Future<RingServerReply> deleteVoip() async {
    deleteVoips++;
    return const RingServerAccepted(serverTs: 1);
  }

  @override
  Future<RingServerReply> deleteDevice() async {
    deleteDevices++;
    if (deleteDeviceError case final Object error) throw error;
    return const RingServerAccepted(serverTs: 1);
  }
}

class _NativeRing {
  String? token = 'dG9rZW4=';
  String environment = 'development';
  bool canRing = true;
  int kid = 1;
  final events = <String>[];
  final calls = <String>[];
  final acked = <int>[];
  final offsets = <int>[];
  final sessions = <bool>[];
  final sessionUsers = <String?>[];
  final nseCalls = <String>[];
  Completer<void>? statusGate;

  Future<Object?> handleRing(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'status':
        await statusGate?.future;
        return {
          'token': token,
          'environment': environment,
          'kid': kid,
          'key': 'a2V5LSRraWQ=',
          'rings': canRing,
        };
      case 'rotateKey':
        kid++;
        return {'kid': kid, 'key': 'bmV3'};
      case 'ackKey':
        acked.add((call.arguments as Map)['kid'] as int);
        offsets.add((call.arguments as Map)['serverOffsetMs'] as int);
      case 'takeEvents':
        final taken = [
          for (final e in events) {'type': e},
        ];
        events.clear();
        return taken;
      case 'setSession':
        sessions.add((call.arguments as Map)['signedIn'] as bool);
        sessionUsers.add((call.arguments as Map)['userId'] as String?);
    }
    return null;
  }

  Future<Object?> handleNse(MethodCall call) async {
    nseCalls.add(call.method);
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _NativeRing native;
  late _FakeServer server;
  late RingRegistration registration;
  late Client client;
  final registeredAt = DateTime.fromMillisecondsSinceEpoch(1789999999000);

  setUp(() {
    ambientCapabilities = capabilitiesLike(iosCapabilities, voipRing: true);
    SharedPreferences.setMockInitialValues({});
    native = _NativeRing();
    server = _FakeServer();
    messenger.setMockMethodCallHandler(ringChannel, native.handleRing);
    messenger.setMockMethodCallHandler(nseChannel, native.handleNse);
    addTearDown(() {
      messenger.setMockMethodCallHandler(ringChannel, null);
      messenger.setMockMethodCallHandler(nseChannel, null);
    });
    client = buildTestClient(userId: '@me:zuno.im', deviceId: 'PHONE')
      ..bearerToken = 'token';
    registration = RingRegistration(server: (_) => server);
  });

  test('a first start rotates the key, opens the session and registers '
      'the token with the development app id', () async {
    await withClock(
      Clock.fixed(registeredAt),
      () => registration.start(client),
    );

    expect(native.calls.take(3), ['status', 'rotateKey', 'setSession']);
    expect(native.sessions, [true]);
    expect(native.sessionUsers, ['@me:zuno.im']);
    expect(server.puts, [
      {
        'appId': voipDevelopmentAppId,
        'pushkey': 'dG9rZW4=',
        'kid': 2,
        'key': 'a2V5LSRraWQ=',
      },
    ]);
    expect(native.acked, [2]);
    expect(registration.state.value, RingRegistrationState.registered);
    expect(registration.current.value, isTrue);
    expect(registration.serverOffsetMs.value, 1000);
  });

  group('the registration lifecycle', () {
    for (final (platform, capabilities) in [
      ('an iPhone', iosCapabilities),
      ('an Android phone', androidCapabilities),
    ]) {
      test('starts on $platform once signed in', () async {
        ambientCapabilities = capabilities;
        final registration = FakeRingRegistration();
        final container = ProviderContainer(
          overrides: [
            matrixClientProvider.overrideWithValue(client),
            platformCapabilitiesProvider.overrideWithValue(capabilities),
            ringRegistrationProvider.overrideWithValue(registration),
          ],
        );
        addTearDown(container.dispose);

        container.listen(ringLifecycleProvider, (_, _) {});
        await pumpEventQueue();

        expect(registration.started, [client]);
      });
    }
  });

  test('a production build registers under the production app id', () async {
    native.environment = 'production';

    await registration.start(client);

    expect(server.puts.single['appId'], voipProductionAppId);
  });

  test(
    'an Android phone registers its FCM token under the FCM app id',
    () async {
      ambientCapabilities = androidCapabilities;

      await registration.start(client);

      expect(server.puts.single['appId'], fcmAppId);
      expect(registration.state.value, RingRegistrationState.registered);
    },
  );

  test('hands native code the server clock offset with the key it '
      'acknowledges', () async {
    await withClock(
      Clock.fixed(registeredAt),
      () => registration.start(client),
    );

    expect(native.offsets, [1000]);
  });

  test('the same session starting again keeps its key', () async {
    await registration.start(client);
    native.calls.clear();

    await registration.start(client);

    expect(native.calls, isNot(contains('rotateKey')));
    expect(server.puts, hasLength(2));
  });

  test('registers whatever the notification permission says', () async {
    installFakePermissions(
      onCheck: permissionDenied,
      onRequest: permissionDenied,
    );

    await registration.start(client);

    expect(registration.state.value, RingRegistrationState.registered);
  });

  test('without CallKit, as on a Mac, nothing registers', () async {
    native.canRing = false;

    await registration.start(client);

    expect(registration.state.value, RingRegistrationState.unavailable);
    expect(server.puts, isEmpty);
    expect(native.sessions, isEmpty);
  });

  test('a later check while the key store cannot answer sends no empty key, '
      'and keeps the registration it has', () async {
    await withClock(
      Clock.fixed(registeredAt),
      () => registration.start(client),
    );
    native.canRing = false;

    await registration.registerNow(client);

    expect(server.puts, hasLength(1));
    expect(registration.state.value, RingRegistrationState.registered);
  });

  test('waits for PushKit to hand over a token, then registers', () {
    fakeAsync((time) {
      native.token = null;
      unawaited(registration.start(client));
      time.flushMicrotasks();
      expect(registration.state.value, RingRegistrationState.waitingForToken);
      expect(server.puts, isEmpty);

      native.token = 'bGF0ZQ==';
      time.elapse(ringTokenWaits.first);
      time.flushMicrotasks();

      expect(server.puts.single['pushkey'], 'bGF0ZQ==');
      expect(registration.state.value, RingRegistrationState.registered);
    });
  });

  test('a server that is not there yet backs off quietly', () {
    fakeAsync((time) {
      server.reply = (_) => const RingServerUnreachable();
      registration.retryDelay = (_) => const Duration(minutes: 1);
      unawaited(registration.start(client));
      time.flushMicrotasks();

      expect(registration.state.value, RingRegistrationState.unreachable);
      expect(registration.current.value, isFalse);

      server.reply = (kid) => RingServerAccepted(serverTs: 5, kid: kid);
      time.elapse(const Duration(minutes: 1));
      time.flushMicrotasks();

      expect(server.puts, hasLength(2));
      expect(registration.state.value, RingRegistrationState.registered);
    });
  });

  test('a server that asks for hours of patience is asked again within the '
      'retry cap', () {
    fakeAsync((time) {
      server.reply = (_) =>
          const RingServerUnreachable(retryAfter: Duration(hours: 5));
      unawaited(registration.start(client));
      time.flushMicrotasks();
      expect(server.puts, hasLength(1));

      server.reply = (kid) => RingServerAccepted(serverTs: 5, kid: kid);
      time.elapse(maxRegistrationRetryDelay);
      time.flushMicrotasks();

      expect(server.puts, hasLength(2));
      expect(registration.state.value, RingRegistrationState.registered);
    });
  });

  test('a refusal from the server is a failure worth showing, kept with '
      'its answer until sign-out', () async {
    const refused = RingServerRefused(
      status: 400,
      errcode: 'M_INVALID_PARAM',
      error: 'unknown app_id',
    );
    server.reply = (_) => refused;

    await withClock(
      Clock.fixed(registeredAt),
      () => registration.start(client),
    );

    expect(registration.state.value, RingRegistrationState.failed);
    final refusal = registration.lastRefusal.value as RingRefusedByServer;
    expect(refusal.reply, refused);
    expect(refusal.at, registeredAt);
    registration.retryDelay = (_) => const Duration(hours: 1);
    await registration.stop(client);
    expect(registration.lastRefusal.value, isNull);
  });

  test('a resume while a refused registration waits for its retry sends '
      'nothing more', () async {
    server.reply = (_) => const RingServerRefused(
      status: 400,
      errcode: 'M_INVALID_PARAM',
      error: 'unknown app_id',
    );
    registration.retryDelay = (_) => const Duration(hours: 1);
    await registration.start(client);
    await registration.recheck(client);
    final sent = server.puts.length;

    await registration.recheck(client);

    expect(server.puts, hasLength(sent));
    await registration.stop(client);
  });

  test('an acknowledgement for another key is a failure', () async {
    server.reply = (_) => const RingServerAccepted(serverTs: 1, kid: 99);

    await registration.start(client);

    expect(registration.state.value, RingRegistrationState.failed);
    expect(native.acked, isEmpty);
    expect(registration.lastRefusal.value, isA<RingKeyNotKept>());
    await registration.stop(client);
  });

  test('a registration that goes through clears the last refusal', () async {
    server.reply = (_) =>
        const RingServerRefused(status: 503, errcode: 'IM.ZUNO.PUSH_DISABLED');
    registration.retryDelay = (_) => const Duration(hours: 1);
    await registration.start(client);
    server.reply = (kid) => RingServerAccepted(serverTs: 1, kid: kid);

    await registration.registerNow(client);

    expect(registration.state.value, RingRegistrationState.registered);
    expect(registration.lastRefusal.value, isNull);
    await registration.stop(client);
  });

  test('a server that cannot be reached keeps the last refusal', () async {
    server.reply = (_) =>
        const RingServerRefused(status: 503, errcode: 'IM.ZUNO.PUSH_DISABLED');
    registration.retryDelay = (_) => const Duration(hours: 1);
    await registration.start(client);
    server.reply = (_) => const RingServerUnreachable();

    await registration.registerNow(client);

    expect(registration.state.value, RingRegistrationState.unreachable);
    expect(registration.lastRefusal.value, isA<RingRefusedByServer>());
    await registration.stop(client);
  });

  test('a new token rotates the key and registers again on resume', () async {
    await registration.start(client);
    native.token = 'bmV3IHRva2Vu';
    native.events.add('token');

    await registration.recheck(client);

    expect(native.calls.where((c) => c == 'rotateKey'), hasLength(2));
    expect(server.puts.last['pushkey'], 'bmV3IHRva2Vu');
  });

  test(
    'a token event for the token already registered changes nothing',
    () async {
      await registration.start(client);
      native.events.add('token');

      await registration.recheck(client);

      expect(native.calls.where((c) => c == 'rotateKey'), hasLength(1));
      expect(server.puts, hasLength(1));
    },
  );

  test(
    'a token that changed without an event registers again on resume',
    () async {
      await registration.start(client);
      native.token = 'bmV3IHRva2Vu';

      await registration.recheck(client);

      expect(server.puts.last['pushkey'], 'bmV3IHRva2Vu');
    },
  );

  test('following a token registers it once', () async {
    await registration.start(client);
    native.token = 'bmV3IHRva2Vu';

    await registration.followToken(client);
    await registration.followToken(client);

    expect(server.puts, hasLength(2));
    expect(server.puts.last['pushkey'], 'bmV3IHRva2Vu');
  });

  test('a forgotten registration waits for a token and follows the next '
      'one', () async {
    await registration.start(client);

    await registration.forget(client);
    expect(registration.state.value, RingRegistrationState.waitingForToken);
    native.token = 'bmV3IHRva2Vu';
    await registration.followToken(client);

    expect(server.puts.last['pushkey'], 'bmV3IHRva2Vu');
    expect(registration.state.value, RingRegistrationState.registered);
  });

  test('a key mismatch registers again with the current key', () async {
    await registration.start(client);
    native.events.add('keyMismatch');

    await registration.recheck(client);

    expect(server.puts, hasLength(2));
    expect(server.puts.last['kid'], server.puts.first['kid']);
  });

  test('an invalidated token is removed from the server', () async {
    await registration.start(client);
    native.token = null;
    native.events.add('invalidated');

    await registration.recheck(client);

    expect(server.deleteVoips, 1);
    expect(registration.current.value, isFalse);
  });

  test('a resume within six hours does not register again', () async {
    await registration.start(client);

    await registration.recheck(client);

    expect(server.puts, hasLength(1));
  });

  test('signing out tells the server and closes the session, leaving the '
      'read model to the sign-out wipe', () async {
    await registration.start(client);

    await registration.stop(client);

    expect(server.deleteDevices, 1);
    expect(native.nseCalls, isEmpty);
    expect(native.sessions, [true, false]);
    expect(registration.state.value, RingRegistrationState.idle);
    expect(registration.current.value, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ringSessionKey), isNull);
    expect(prefs.getString(ringAckedKey), isNull);
  });

  test(
    'signing out with nothing registered asks nothing of the server',
    () async {
      await registration.stop(client);

      expect(server.deleteDevices, 0);
      expect(native.calls, isEmpty);
    },
  );

  test(
    'signing out after the session already ended still closes it here',
    () async {
      await registration.start(client);
      client.bearerToken = null;

      await registration.stop(client);

      expect(server.deleteDevices, 0);
      expect(native.nseCalls, isEmpty);
      expect(native.sessions, [true, false]);
    },
  );

  test('a sign-out while a start is still under way ends signed out, and '
      'nothing registers after it', () async {
    final gate = Completer<void>();
    native.statusGate = gate;

    final starting = registration.start(client);
    final stopping = registration.stop(client);
    gate.complete();
    await Future.wait([starting, stopping]);
    await registration.registerNow(client);

    expect(native.sessions, [true, false]);
    expect(server.deleteDevices, 1);
    expect(server.puts, hasLength(1));
    expect(registration.state.value, RingRegistrationState.idle);
  });

  test('a start that runs after a sign-out touches no key', () async {
    client.bearerToken = null;

    await registration.start(client);

    expect(native.calls, isEmpty);
  });

  test('a registration queued from before a sign-out touches no key after '
      'it', () async {
    await registration.start(client);
    native.calls.clear();
    client.bearerToken = null;

    await registration.registerNow(client);

    expect(native.calls, isEmpty);
  });

  test('signing out with no network still closes the session', () async {
    await registration.start(client);
    server.deleteDeviceError = const SocketException('offline');

    await registration.stop(client);

    expect(server.deleteDevices, 1);
    expect(native.sessions, [true, false]);
    expect(registration.state.value, RingRegistrationState.idle);
  });
}
