import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, debugPrint;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../async/serial_lock.dart';
import '../../errors/caught_errors.dart';
import '../../matrix/matrix_client_provider.dart';
import '../delivery/registration_retry.dart';
import 'ring_channel.dart';
import 'ring_server.dart';

const ringSessionKey = 'push.voip.session';
const ringAckedKey = 'push.voip.acked';

const ringTokenWaits = [
  Duration(seconds: 5),
  Duration(seconds: 30),
  Duration(minutes: 2),
];

sealed class RingRefusal {
  const RingRefusal({required this.at});

  final DateTime at;
}

final class RingRefusedByServer extends RingRefusal {
  const RingRefusedByServer({required super.at, required this.reply});

  final RingServerRefused reply;
}

final class RingKeyNotKept extends RingRefusal {
  const RingKeyNotKept({required super.at});
}

enum RingRegistrationState {
  idle,
  unavailable,
  waitingForToken,
  registering,
  registered,
  unreachable,
  failed,
}

class RingRegistration {
  RingRegistration({RingServer Function(Client client)? server})
    : _server = server ?? ZunoPushRingServer.new;

  final _channel = const RingChannel();
  final RingServer Function(Client client) _server;
  final _lock = SerialLock();
  final _retry = RegistrationRetry();
  final _recheck = RegistrationRecheck();
  final _state = ValueNotifier(RingRegistrationState.idle);
  final _lastRefusal = ValueNotifier<RingRefusal?>(null);
  final _current = ValueNotifier(false);
  final _serverOffsetMs = ValueNotifier<int?>(null);
  Timer? _tokenWait;
  int _tokenWaits = 0;

  set retryDelay(Duration Function(int attempt) delay) => _retry.delay = delay;

  ValueListenable<RingRegistrationState> get state => _state;

  ValueListenable<RingRefusal?> get lastRefusal => _lastRefusal;

  ValueListenable<bool> get current => _current;

  ValueListenable<int?> get serverOffsetMs => _serverOffsetMs;

  bool get _inactive =>
      _state.value == RingRegistrationState.idle ||
      _state.value == RingRegistrationState.unavailable;

  Future<void> start(Client client) => _lock.run(() async {
    if (!client.isLogged()) return;
    final status = await _channel.status();
    final session = _sessionOf(client);
    if (status == null || session == null) return;
    if (!status.canRing) {
      _state.value = RingRegistrationState.unavailable;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(ringSessionKey) != session) {
      await _channel.rotateKey();
      await prefs.setString(ringSessionKey, session);
      await prefs.remove(ringAckedKey);
    }
    await _channel.setSession(signedIn: true, userId: client.userID);
    await _drainEvents(client);
    await _register(client);
  });

  Future<void> recheck(Client client) => _lock.run(() async {
    if (_inactive) return;
    final changed = await _drainEvents(client);
    if (changed ||
        _recheck.claimDue() ||
        (!_retry.scheduled && await _tokenUnregistered())) {
      await _register(client);
    }
  });

  Future<void> followToken(Client client) => _lock.run(() async {
    if (_inactive || !await _tokenUnregistered()) return;
    await _register(client);
  });

  Future<void> registerNow(Client client) => _lock.run(() async {
    if (_inactive) return;
    _retry.reset();
    await _register(client);
  });

  Future<void> stop(Client client) => _lock.run(() async {
    _cancelTimers();
    final prefs = await SharedPreferences.getInstance();
    final hadSession = prefs.getString(ringSessionKey) != null;
    if (!hadSession && _state.value == RingRegistrationState.idle) return;
    if (client.isLogged()) {
      try {
        await _server(client).deleteDevice();
      } catch (e, s) {
        reportCaught('ring device forget', e, s);
      }
    }
    _current.value = false;
    _serverOffsetMs.value = null;
    _lastRefusal.value = null;
    _state.value = RingRegistrationState.idle;
    await _channel.setSession(signedIn: false);
    await prefs.remove(ringSessionKey);
    await prefs.remove(ringAckedKey);
  });

  Future<void> forget(Client client) => _lock.run(() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(ringAckedKey) == null) return;
    await _forgetToken(client);
    if (!_inactive) _state.value = RingRegistrationState.waitingForToken;
  });

  Future<bool> _drainEvents(Client client) async {
    var changed = false;
    for (final event in await _channel.takeEvents()) {
      switch (event) {
        case RingRegistrationEvent.token:
          final status = await _channel.status();
          if (status != null && !await _ackedFor(status)) {
            await _channel.rotateKey();
            changed = true;
          }
        case RingRegistrationEvent.keyMismatch:
          changed = true;
        case RingRegistrationEvent.invalidated:
          await _forgetToken(client);
      }
    }
    return changed;
  }

  Future<void> _register(Client client) async {
    if (!client.isLogged()) return;
    final status = await _channel.status();
    if (status == null || !status.canRing) return;
    final token = status.token;
    if (token == null) {
      _state.value = RingRegistrationState.waitingForToken;
      _waitForToken(client);
      return;
    }
    _tokenWait?.cancel();
    _tokenWaits = 0;
    _state.value = RingRegistrationState.registering;
    final appId = status.appId;
    final RingServerReply reply;
    try {
      reply = await _server(
        client,
      ).putVoip(appId: appId, pushkey: token, kid: status.kid, key: status.key);
    } catch (e, s) {
      reportCaught('ring register', e, s);
      _quietRetry(client, null);
      return;
    }
    switch (reply) {
      case RingServerAccepted(:final serverTs, :final kid)
          when kid == null || kid == status.kid:
        final offset = serverTs - clock.now().millisecondsSinceEpoch;
        await _channel.ackKey(status.kid, serverOffsetMs: offset);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(ringAckedKey, _ackOf(appId, token, status.kid));
        _serverOffsetMs.value = offset;
        _current.value = true;
        _recheck.markChecked();
        _retry.reset();
        _lastRefusal.value = null;
        _state.value = RingRegistrationState.registered;
      case RingServerAccepted(:final kid):
        debugPrint('zuno/ring: the server kept key $kid, not ${status.kid}');
        _fail(client, RingKeyNotKept(at: clock.now()));
      case RingServerUnreachable(:final retryAfter):
        _quietRetry(client, retryAfter);
      case final RingServerRefused refused:
        debugPrint(
          'zuno/ring: the server refused this device '
          '(${refused.status} ${refused.errcode})',
        );
        _fail(client, RingRefusedByServer(at: clock.now(), reply: refused));
    }
  }

  void _quietRetry(Client client, Duration? after) {
    _state.value = RingRegistrationState.unreachable;
    _scheduleRetry(client, after);
  }

  void _fail(Client client, RingRefusal refusal) {
    _lastRefusal.value = refusal;
    _state.value = RingRegistrationState.failed;
    _scheduleRetry(client, null);
  }

  void _scheduleRetry(Client client, Duration? after) {
    if (after == null) {
      _retry.schedule(() => _lock.run(() => _register(client)));
      return;
    }
    _retry.cancel();
    _tokenWait?.cancel();
    _tokenWait = Timer(
      after > maxRegistrationRetryDelay ? maxRegistrationRetryDelay : after,
      () => unawaited(registerNow(client)),
    );
  }

  void _waitForToken(Client client) {
    if (_tokenWaits >= ringTokenWaits.length) return;
    final delay = ringTokenWaits[_tokenWaits++];
    _tokenWait?.cancel();
    _tokenWait = Timer(delay, () => unawaited(registerNow(client)));
  }

  Future<void> _forgetToken(Client client) async {
    try {
      await _server(client).deleteVoip();
    } catch (e, s) {
      reportCaught('ring token forget', e, s);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(ringAckedKey);
    _current.value = false;
  }

  Future<bool> _tokenUnregistered() async {
    final status = await _channel.status();
    return status?.token != null && !await _ackedFor(status!);
  }

  Future<bool> _ackedFor(RingStatus status) async {
    final token = status.token;
    if (token == null) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(ringAckedKey) ==
        _ackOf(status.appId, token, status.kid);
  }

  String _ackOf(String appId, String token, int kid) => '$appId|$token|$kid';

  String? _sessionOf(Client client) {
    final user = client.userID;
    final device = client.deviceID;
    if (user == null || device == null) return null;
    return '$user|$device';
  }

  void _cancelTimers() {
    _retry.reset();
    _tokenWait?.cancel();
    _tokenWait = null;
    _tokenWaits = 0;
  }
}

final ringRegistration = RingRegistration();

final ringRegistrationProvider = Provider<RingRegistration>(
  (ref) => ringRegistration,
);

final ringLifecycleProvider = Provider<void>((ref) {
  final client = ref.watch(matrixClientProvider);
  final registration = ref.watch(ringRegistrationProvider);
  ref.listen(isLoggedInProvider, (_, loggedIn) {
    if (loggedIn.value == true) unawaited(registration.start(client));
  }, fireImmediately: true);
  final lifecycle = AppLifecycleListener(
    onResume: () {
      if (client.isLogged()) unawaited(registration.recheck(client));
    },
  );
  ref.onDispose(lifecycle.dispose);
});
