import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/read_model/nse_channel.dart';
import 'package:zuno/core/push/registration_retry.dart';
import 'package:zuno/core/push/voip/voip_channel.dart';
import 'package:zuno/core/push/voip/voip_registration.dart';
import 'package:zuno/core/push/voip/voip_server.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_permissions.dart';
import '../../../helpers/platform_capabilities.dart';

class _FakeServer implements VoipServer {
  final puts = <Map<String, Object>>[];
  var deleteVoips = 0;
  var deleteDevices = 0;
  Object? deleteDeviceError;
  VoipServerReply Function(int kid) reply = (kid) =>
      VoipServerAccepted(serverTs: 1790000000000, kid: kid);

  @override
  Future<VoipServerReply> putVoip({
    required String appId,
    required String pushkey,
    required int kid,
    required String key,
  }) async {
    puts.add({'appId': appId, 'pushkey': pushkey, 'kid': kid, 'key': key});
    return reply(kid);
  }

  @override
  Future<VoipServerReply> deleteVoip() async {
    deleteVoips++;
    return const VoipServerAccepted(serverTs: 1);
  }

  @override
  Future<VoipServerReply> deleteDevice() async {
    deleteDevices++;
    if (deleteDeviceError case final Object error) throw error;
    return const VoipServerAccepted(serverTs: 1);
  }
}

class _NativeVoip {
  String? token = 'dG9rZW4=';
  String environment = 'development';
  bool callKit = true;
  int kid = 1;
  final events = <String>[];
  final calls = <String>[];
  final acked = <int>[];
  final sessions = <bool>[];
  final nseCalls = <String>[];
  var wipes = 0;
  Completer<void>? statusGate;

  Future<Object?> handleVoip(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'status':
        await statusGate?.future;
        return {
          'token': token,
          'environment': environment,
          'kid': kid,
          'key': 'a2V5LSRraWQ=',
          'callkit': callKit,
        };
      case 'rotateKey':
        kid++;
        return {'kid': kid, 'key': 'bmV3'};
      case 'ackKey':
        acked.add((call.arguments as Map)['kid'] as int);
      case 'takeEvents':
        final taken = [
          for (final e in events) {'type': e},
        ];
        events.clear();
        return taken;
      case 'setSession':
        sessions.add((call.arguments as Map)['signedIn'] as bool);
    }
    return null;
  }

  Future<Object?> handleNse(MethodCall call) async {
    nseCalls.add(call.method);
    if (call.method == 'wipe') wipes++;
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _NativeVoip native;
  late _FakeServer server;
  late VoipRegistration registration;
  late Client client;

  setUp(() {
    ambientCapabilities = capabilitiesLike(iosCapabilities, voipRing: true);
    SharedPreferences.setMockInitialValues({});
    native = _NativeVoip();
    server = _FakeServer();
    messenger.setMockMethodCallHandler(voipChannel, native.handleVoip);
    messenger.setMockMethodCallHandler(nseChannel, native.handleNse);
    addTearDown(() {
      messenger.setMockMethodCallHandler(voipChannel, null);
      messenger.setMockMethodCallHandler(nseChannel, null);
    });
    client = buildTestClient(userId: '@me:zuno.im', deviceId: 'PHONE');
    registration = VoipRegistration(server: (_) => server)
      ..now = () => DateTime.fromMillisecondsSinceEpoch(1789999999000);
  });

  test('a first start rotates the key, opens the session and registers '
      'the token with the development app id', () async {
    await registration.start(client);

    expect(native.calls.take(3), ['status', 'rotateKey', 'setSession']);
    expect(native.sessions, [true]);
    expect(server.puts, [
      {
        'appId': voipDevelopmentAppId,
        'pushkey': 'dG9rZW4=',
        'kid': 2,
        'key': 'a2V5LSRraWQ=',
      },
    ]);
    expect(native.acked, [2]);
    expect(registration.state.value, VoipRegistrationState.registered);
    expect(registration.current.value, isTrue);
    expect(registration.serverOffsetMs.value, 1000);
  });

  test('a production build registers under the production app id', () async {
    native.environment = 'production';

    await registration.start(client);

    expect(server.puts.single['appId'], voipProductionAppId);
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

    expect(registration.state.value, VoipRegistrationState.registered);
  });

  test('without CallKit, as on a Mac, nothing registers', () async {
    native.callKit = false;

    await registration.start(client);

    expect(registration.state.value, VoipRegistrationState.unavailable);
    expect(server.puts, isEmpty);
    expect(native.sessions, isEmpty);
  });

  test(
    'with the flag off nothing is asked of native code or the server',
    () async {
      ambientCapabilities = capabilitiesLike(iosCapabilities, voipRing: false);
      registration = VoipRegistration(server: (_) => server);

      await registration.start(client);

      expect(native.calls, isEmpty);
      expect(server.puts, isEmpty);
      expect(registration.state.value, VoipRegistrationState.idle);
    },
  );

  test('waits for PushKit to hand over a token, then registers', () {
    fakeAsync((time) {
      native.token = null;
      unawaited(registration.start(client));
      time.flushMicrotasks();
      expect(registration.state.value, VoipRegistrationState.waitingForToken);
      expect(server.puts, isEmpty);

      native.token = 'bGF0ZQ==';
      time.elapse(voipTokenWaits.first);
      time.flushMicrotasks();

      expect(server.puts.single['pushkey'], 'bGF0ZQ==');
      expect(registration.state.value, VoipRegistrationState.registered);
    });
  });

  test('a server that is not there yet backs off quietly', () {
    fakeAsync((time) {
      server.reply = (_) => const VoipServerUnreachable();
      registration.retryDelay = (_) => const Duration(minutes: 1);
      unawaited(registration.start(client));
      time.flushMicrotasks();

      expect(registration.state.value, VoipRegistrationState.unreachable);
      expect(registration.current.value, isFalse);

      server.reply = (kid) => VoipServerAccepted(serverTs: 5, kid: kid);
      time.elapse(const Duration(minutes: 1));
      time.flushMicrotasks();

      expect(server.puts, hasLength(2));
      expect(registration.state.value, VoipRegistrationState.registered);
    });
  });

  test('a server that asks for hours of patience is asked again within the '
      'retry cap', () {
    fakeAsync((time) {
      server.reply = (_) =>
          const VoipServerUnreachable(retryAfter: Duration(hours: 5));
      unawaited(registration.start(client));
      time.flushMicrotasks();
      expect(server.puts, hasLength(1));

      server.reply = (kid) => VoipServerAccepted(serverTs: 5, kid: kid);
      time.elapse(maxRegistrationRetryDelay);
      time.flushMicrotasks();

      expect(server.puts, hasLength(2));
      expect(registration.state.value, VoipRegistrationState.registered);
    });
  });

  test('a refusal from the server is a failure worth showing, kept with '
      'its answer until sign-out', () async {
    const refused = VoipServerRefused(
      status: 400,
      errcode: 'M_INVALID_PARAM',
      error: 'unknown app_id',
    );
    server.reply = (_) => refused;

    await registration.start(client);

    expect(registration.state.value, VoipRegistrationState.failed);
    final refusal = registration.lastRefusal.value as VoipRefusedByServer;
    expect(refusal.reply, refused);
    expect(refusal.at, DateTime.fromMillisecondsSinceEpoch(1789999999000));
    registration.retryDelay = (_) => const Duration(hours: 1);
    await registration.stop(client);
    expect(registration.lastRefusal.value, isNull);
  });

  test('an acknowledgement for another key is a failure', () async {
    server.reply = (_) => const VoipServerAccepted(serverTs: 1, kid: 99);

    await registration.start(client);

    expect(registration.state.value, VoipRegistrationState.failed);
    expect(native.acked, isEmpty);
    expect(registration.lastRefusal.value, isA<VoipKeyNotKept>());
    await registration.stop(client);
  });

  test('a registration that goes through clears the last refusal', () async {
    server.reply = (_) =>
        const VoipServerRefused(status: 503, errcode: 'IM.ZUNO.PUSH_DISABLED');
    registration.retryDelay = (_) => const Duration(hours: 1);
    await registration.start(client);
    server.reply = (kid) => VoipServerAccepted(serverTs: 1, kid: kid);

    await registration.registerNow(client);

    expect(registration.state.value, VoipRegistrationState.registered);
    expect(registration.lastRefusal.value, isNull);
    await registration.stop(client);
  });

  test('a server that cannot be reached keeps the last refusal', () async {
    server.reply = (_) =>
        const VoipServerRefused(status: 503, errcode: 'IM.ZUNO.PUSH_DISABLED');
    registration.retryDelay = (_) => const Duration(hours: 1);
    await registration.start(client);
    server.reply = (_) => const VoipServerUnreachable();

    await registration.registerNow(client);

    expect(registration.state.value, VoipRegistrationState.unreachable);
    expect(registration.lastRefusal.value, isA<VoipRefusedByServer>());
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

  test('a key mismatch registers again with the current key', () async {
    await registration.start(client);
    native.events.add('keyMismatch');

    await registration.recheck(client);

    expect(server.puts, hasLength(2));
    expect(server.puts.last['kid'], server.puts.first['kid']);
  });

  test('an invalidated token is removed from the server', () async {
    await registration.start(client);
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

  test('signing out tells the server, wipes the read model and closes the '
      'session', () async {
    client.bearerToken = 'token';
    await registration.start(client);

    await registration.stop(client);

    expect(server.deleteDevices, 1);
    expect(native.wipes, 1);
    expect(native.sessions, [true, false]);
    expect(registration.state.value, VoipRegistrationState.idle);
    expect(registration.current.value, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(voipSessionKey), isNull);
    expect(prefs.getString(voipAckedKey), isNull);
  });

  test('signing out wipes the read model last, after the meta write its own '
      'reset triggers', () async {
    client.bearerToken = 'token';
    await registration.start(client);
    registration.current.addListener(
      () => unawaited(const NseChannel().writeMeta('{}')),
    );
    native.nseCalls.clear();

    await registration.stop(client);

    expect(native.nseCalls, ['writeMeta', 'wipe']);
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

      await registration.stop(client);

      expect(server.deleteDevices, 0);
      expect(native.wipes, 1);
      expect(native.sessions, [true, false]);
    },
  );

  test('a sign-out while a start is still under way ends signed out, and '
      'nothing registers after it', () async {
    client.bearerToken = 'token';
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
    expect(registration.state.value, VoipRegistrationState.idle);
  });

  test('signing out with no network still wipes the read model and closes '
      'the session', () async {
    client.bearerToken = 'token';
    await registration.start(client);
    server.deleteDeviceError = const SocketException('offline');

    await registration.stop(client);

    expect(server.deleteDevices, 1);
    expect(native.wipes, 1);
    expect(native.sessions, [true, false]);
    expect(registration.state.value, VoipRegistrationState.idle);
  });
}
