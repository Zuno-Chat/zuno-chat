import 'dart:async';

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, debugPrint, visibleForTesting;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../calls/serial_lock.dart';
import '../../matrix/matrix_client_provider.dart';
import '../../platform/platform_capabilities.dart';
import '../read_model/nse_channel.dart';
import '../registration_retry.dart';
import 'voip_channel.dart';
import 'voip_server.dart';

const voipProductionAppId = 'im.zuno.chat.ios.voip';
const voipDevelopmentAppId = 'im.zuno.chat.ios.dev.voip';

const voipSessionKey = 'push.voip.session';
const voipAckedKey = 'push.voip.acked';

const voipTokenWaits = [
  Duration(seconds: 5),
  Duration(seconds: 30),
  Duration(minutes: 2),
];

String voipAppIdFor(String environment) =>
    environment == 'development' ? voipDevelopmentAppId : voipProductionAppId;

sealed class VoipRefusal {
  const VoipRefusal({required this.at});

  final DateTime at;
}

final class VoipRefusedByServer extends VoipRefusal {
  const VoipRefusedByServer({required super.at, required this.reply});

  final VoipServerRefused reply;
}

final class VoipKeyNotKept extends VoipRefusal {
  const VoipKeyNotKept({required super.at});
}

enum VoipRegistrationState {
  idle,
  unavailable,
  waitingForToken,
  registering,
  registered,
  unreachable,
  failed,
}

class VoipRegistration {
  VoipRegistration({
    VoipChannel voip = const VoipChannel(),
    NseChannel nse = const NseChannel(),
    VoipServer Function(Client client)? server,
  }) : _channel = voip,
       _readModel = nse,
       _server = server ?? ZunoPushVoipServer.new;

  final VoipChannel _channel;
  final NseChannel _readModel;
  final VoipServer Function(Client client) _server;
  final _lock = SerialLock();
  final _retry = RegistrationRetry();
  final _recheck = RegistrationRecheck();
  final _state = ValueNotifier(VoipRegistrationState.idle);
  final _lastRefusal = ValueNotifier<VoipRefusal?>(null);
  final _current = ValueNotifier(false);
  final _serverOffsetMs = ValueNotifier<int?>(null);
  Timer? _tokenWait;
  int _tokenWaits = 0;

  @visibleForTesting
  DateTime Function() now = DateTime.now;

  set retryDelay(Duration Function(int attempt) delay) => _retry.delay = delay;

  ValueListenable<VoipRegistrationState> get state => _state;

  ValueListenable<VoipRefusal?> get lastRefusal => _lastRefusal;

  ValueListenable<bool> get current => _current;

  ValueListenable<int?> get serverOffsetMs => _serverOffsetMs;

  bool get _inactive =>
      _state.value == VoipRegistrationState.idle ||
      _state.value == VoipRegistrationState.unavailable;

  Future<void> start(Client client) => _lock.run(() async {
    final status = await _channel.status();
    final session = _sessionOf(client);
    if (status == null || session == null) return;
    if (!status.callKit) {
      _state.value = VoipRegistrationState.unavailable;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(voipSessionKey) != session) {
      await _channel.rotateKey();
      await prefs.setString(voipSessionKey, session);
      await prefs.remove(voipAckedKey);
    }
    await _channel.setSession(signedIn: true);
    await _drainEvents(client);
    await _register(client);
  });

  Future<void> recheck(Client client) => _lock.run(() async {
    if (_inactive) return;
    final changed = await _drainEvents(client);
    if (changed || _recheck.claimDue()) await _register(client);
  });

  Future<void> registerNow(Client client) => _lock.run(() async {
    if (_inactive) return;
    _retry.reset();
    await _register(client);
  });

  Future<void> stop(Client client) => _lock.run(() async {
    _cancelTimers();
    final prefs = await SharedPreferences.getInstance();
    final hadSession = prefs.getString(voipSessionKey) != null;
    if (!hadSession && _state.value == VoipRegistrationState.idle) return;
    if (client.isLogged()) {
      try {
        await _server(client).deleteDevice();
      } catch (_) {
        debugPrint('zuno/voip: the server was not told to forget this device');
      }
    }
    _current.value = false;
    _serverOffsetMs.value = null;
    _lastRefusal.value = null;
    _state.value = VoipRegistrationState.idle;
    await _readModel.wipe();
    await _channel.setSession(signedIn: false);
    await prefs.remove(voipSessionKey);
    await prefs.remove(voipAckedKey);
  });

  Future<bool> _drainEvents(Client client) async {
    var changed = false;
    for (final event in await _channel.takeEvents()) {
      switch (event) {
        case VoipEvent.token:
          final status = await _channel.status();
          if (status != null && !await _ackedFor(status)) {
            await _channel.rotateKey();
            changed = true;
          }
        case VoipEvent.keyMismatch:
          changed = true;
        case VoipEvent.invalidated:
          await _forgetToken(client);
      }
    }
    return changed;
  }

  Future<void> _register(Client client) async {
    final status = await _channel.status();
    if (status == null) return;
    final token = status.token;
    if (token == null) {
      _state.value = VoipRegistrationState.waitingForToken;
      _waitForToken(client);
      return;
    }
    _tokenWait?.cancel();
    _tokenWaits = 0;
    _state.value = VoipRegistrationState.registering;
    final appId = voipAppIdFor(status.environment);
    final VoipServerReply reply;
    try {
      reply = await _server(
        client,
      ).putVoip(appId: appId, pushkey: token, kid: status.kid, key: status.key);
    } catch (_) {
      _quietRetry(client, null);
      return;
    }
    switch (reply) {
      case VoipServerAccepted(:final serverTs, :final kid)
          when kid == null || kid == status.kid:
        await _channel.ackKey(status.kid);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(voipAckedKey, _ackOf(appId, token, status.kid));
        _serverOffsetMs.value = serverTs - now().millisecondsSinceEpoch;
        _current.value = true;
        _recheck.markChecked();
        _retry.reset();
        _lastRefusal.value = null;
        _state.value = VoipRegistrationState.registered;
      case VoipServerAccepted(:final kid):
        debugPrint('zuno/voip: the server kept key $kid, not ${status.kid}');
        _fail(client, VoipKeyNotKept(at: now()));
      case VoipServerUnreachable(:final retryAfter):
        _quietRetry(client, retryAfter);
      case final VoipServerRefused refused:
        debugPrint(
          'zuno/voip: the server refused this device '
          '(${refused.status} ${refused.errcode})',
        );
        _fail(client, VoipRefusedByServer(at: now(), reply: refused));
    }
  }

  void _quietRetry(Client client, Duration? after) {
    _state.value = VoipRegistrationState.unreachable;
    _scheduleRetry(client, after);
  }

  void _fail(Client client, VoipRefusal refusal) {
    _lastRefusal.value = refusal;
    _state.value = VoipRegistrationState.failed;
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
    if (_tokenWaits >= voipTokenWaits.length) return;
    final delay = voipTokenWaits[_tokenWaits++];
    _tokenWait?.cancel();
    _tokenWait = Timer(delay, () => unawaited(registerNow(client)));
  }

  Future<void> _forgetToken(Client client) async {
    try {
      await _server(client).deleteVoip();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(voipAckedKey);
    _current.value = false;
  }

  Future<bool> _ackedFor(VoipStatus status) async {
    final token = status.token;
    if (token == null) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(voipAckedKey) ==
        _ackOf(voipAppIdFor(status.environment), token, status.kid);
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

final voipRegistration = VoipRegistration();

final voipRegistrationProvider = Provider<VoipRegistration>(
  (ref) => voipRegistration,
);

final voipLifecycleProvider = Provider<void>((ref) {
  if (!ref.watch(platformCapabilitiesProvider).voipRing) return;
  final client = ref.watch(matrixClientProvider);
  final registration = ref.watch(voipRegistrationProvider);
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
