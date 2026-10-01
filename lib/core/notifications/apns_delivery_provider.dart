import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../matrix/session_display_name.dart';
import '../platform/platform_capabilities.dart';
import '../push/apns_pusher.dart';
import '../push/fcm_gateway.dart';
import '../push/pusher_reconciliation.dart';
import '../push/registration_retry.dart';
import 'notification_delivery_provider.dart';
import 'notification_permission.dart';
import 'notification_sound_settings.dart';

enum ApnsStatus {
  idle,
  registering,
  tokenFailed,
  postingPusher,
  ready,
  pusherFailed,
}

const _channel = MethodChannel('zuno/apns');

const _tokenKey = 'push.apns.token';
const _appIdKey = 'push.apns.app_id';
const _droppedKey = 'push.apns.dropped';
const _soundKey = 'push.apns.sound';

typedef _Registration = ({String appId, String token, String pushkey});

class ApnsDeliveryProvider implements NotificationDeliveryProvider {
  ApnsDeliveryProvider({PlatformCapabilities? capabilities})
    : _injectedCapabilities = capabilities;

  final PlatformCapabilities? _injectedCapabilities;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  final status = ValueNotifier<ApnsStatus>(ApnsStatus.idle);

  final dropped = ValueNotifier<int>(0);

  String? lastPusherError;

  @visibleForTesting
  String appId = apnsAppId;

  _Registration? _registration;
  String? get token => _registration?.token;
  String? get pushkey => _registration?.pushkey;

  bool? _postedSound;
  bool _syncingSound = false;
  bool _soundChanged = false;

  @visibleForTesting
  Future<String?> Function() tokenReader = () =>
      _channel.invokeMethod<String>('getToken');

  @visibleForTesting
  Future<bool> Function() notificationsAllowed = mayRegisterForNotifications;

  final _retry = RegistrationRetry();

  set retryDelay(Duration Function(int attempt) delay) => _retry.delay = delay;

  bool get retryScheduled => _retry.scheduled;

  final _recheck = RegistrationRecheck();

  set now(DateTime Function() value) => _recheck.now = value;

  @override
  Future<void> start(Client client) async {
    if (!_capabilities.apnsRegistration) return;
    if (status.value != ApnsStatus.idle) return;
    if (!await notificationsAllowed()) return;
    final stored = await _storedRegistration();
    if (stored == null) {
      await _register(client);
      return;
    }
    _registration = stored;
    dropped.value = await _storedDropped();
    _postedSound = await _storedSound();
    lastPusherError = null;
    status.value = ApnsStatus.ready;
    _recheck.markChecked();
    if (stored.appId != appId) {
      await _register(client);
      return;
    }

    final String? current;
    try {
      current = await tokenReader();
    } catch (e) {
      debugPrint(
        'zuno/push: APNs token check failed, keeping registration ($e)',
      );
      return;
    }
    if (current != null && current.isNotEmpty && current != stored.token) {
      await _register(client);
      return;
    }
    await _reconcile(client, stored);
    await _syncSound(client);
  }

  Future<void> retryIfFailed(Client client) async {
    if (status.value != ApnsStatus.tokenFailed &&
        status.value != ApnsStatus.pusherFailed) {
      return;
    }
    _retry.cancel();
    await _register(client);
  }

  Future<void> recheckRegistration(Client client) async {
    final registration = _registration;
    if (status.value != ApnsStatus.ready || registration == null) return;
    if (_recheck.claimDue()) await _reconcile(client, registration);
    await _syncSound(client);
  }

  Future<void> messageToneChanged(Client client) => _syncSound(client);

  Future<void> registerNow(Client client) async {
    if (!_capabilities.apnsRegistration) return;
    dropped.value = 0;
    await _storeDropped(0);
    await _register(client);
  }

  Future<void> _reconcile(Client client, _Registration registration) async {
    final registered = await pusherIsRegistered(
      client,
      appId: registration.appId,
      pushkey: registration.pushkey,
    );
    if (registered != false) return;
    dropped.value += 1;
    await _storeDropped(dropped.value);
    debugPrint(
      'zuno/push: the homeserver dropped the APNs pusher '
      '(${dropped.value}x), registering again',
    );
    await _register(client);
  }

  Future<void> _register(Client client) async {
    if (!_capabilities.apnsRegistration) return;
    if (!await notificationsAllowed()) return;

    status.value = ApnsStatus.registering;
    final String? token;
    try {
      token = await tokenReader();
    } catch (e) {
      debugPrint('zuno/push: APNs token request failed ($e)');
      status.value = ApnsStatus.tokenFailed;
      _retry.schedule(() => _register(client));
      return;
    }
    final pushkey = token == null ? null : apnsPushkeyFromToken(token);
    if (token == null || pushkey == null) {
      if (token != null) {
        debugPrint('zuno/push: APNs token is not hex, refusing to register');
      }
      status.value = ApnsStatus.tokenFailed;
      _retry.schedule(() => _register(client));
      return;
    }

    status.value = ApnsStatus.postingPusher;
    final sound = await _messageTone();
    final posted = await _post(
      client,
      appId: appId,
      pushkey: pushkey,
      sound: sound,
    );
    if (!posted) return;
    final previous = _registration ?? await _storedRegistration();
    final registration = (appId: appId, token: token, pushkey: pushkey);
    _registration = registration;
    lastPusherError = null;
    status.value = ApnsStatus.ready;
    _recheck.markChecked();
    _retry.reset();
    await _remember(registration);
    if (previous != null &&
        (previous.appId != appId || previous.pushkey != pushkey)) {
      await _forget(client, previous);
    }
    await _syncSound(client);
  }

  Future<void> _syncSound(Client client) async {
    _soundChanged = true;
    if (_syncingSound) return;
    _syncingSound = true;
    try {
      while (_soundChanged) {
        _soundChanged = false;
        final registration = _registration;
        if (status.value != ApnsStatus.ready || registration == null) return;
        final sound = await _messageTone();
        if (sound == _postedSound) continue;
        final gatewayUrl = fcmGatewayUri(client.homeserver);
        if (gatewayUrl == null) return;
        try {
          await _send(
            client,
            appId: registration.appId,
            pushkey: registration.pushkey,
            gatewayUrl: gatewayUrl,
            sound: sound,
          );
        } catch (e) {
          debugPrint(
            'zuno/push: Message tone not on the APNs pusher yet, trying '
            'again on resume ($e)',
          );
          return;
        }
        _soundChanged = true;
      }
    } finally {
      _syncingSound = false;
    }
  }

  Future<bool> _post(
    Client client, {
    required String appId,
    required String pushkey,
    required bool sound,
  }) async {
    final gatewayUrl = fcmGatewayUri(client.homeserver);
    if (gatewayUrl == null) {
      lastPusherError = 'No server to send notifications through yet.';
      status.value = ApnsStatus.pusherFailed;
      return false;
    }
    try {
      await _send(
        client,
        appId: appId,
        pushkey: pushkey,
        gatewayUrl: gatewayUrl,
        sound: sound,
      );
    } catch (e) {
      lastPusherError = e.toString();
      status.value = ApnsStatus.pusherFailed;
      _retry.schedule(() => _register(client));
      return false;
    }
    return true;
  }

  Future<void> _send(
    Client client, {
    required String appId,
    required String pushkey,
    required Uri gatewayUrl,
    required bool sound,
  }) async {
    await client.postPusher(
      buildApnsPusher(
        appId: appId,
        pushkey: pushkey,
        gatewayUrl: gatewayUrl,
        deviceDisplayName: sessionDisplayName('ios'),
        sound: sound,
      ),
    );
    _postedSound = sound;
    await _storeSound(sound);
  }

  @override
  Future<void> stop(Client client) async {
    _retry.reset();
    final registration = _registration ?? await _storedRegistration();
    if (registration == null && status.value == ApnsStatus.idle) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_appIdKey);
      await prefs.remove(_droppedKey);
      await prefs.remove(_soundKey);
    } catch (e) {
      debugPrint('zuno/push: could not forget the APNs registration ($e)');
    }
    if (registration != null) {
      try {
        await client.deletePusher(_pusherId(registration));
        lastPusherError = null;
      } catch (e) {
        lastPusherError = 'Could not remove the push registration: $e';
      }
    }
    _registration = null;
    _postedSound = null;
    dropped.value = 0;
    status.value = ApnsStatus.idle;
  }

  Future<void> _forget(Client client, _Registration registration) async {
    try {
      await client.deletePusher(_pusherId(registration));
    } catch (e) {
      debugPrint('zuno/push: could not remove the old APNs pusher ($e)');
    }
  }

  PusherId _pusherId(_Registration registration) =>
      PusherId(appId: registration.appId, pushkey: registration.pushkey);

  Future<_Registration?> _storedRegistration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      if (token == null) return null;
      final pushkey = apnsPushkeyFromToken(token);
      if (pushkey == null) return null;
      return (
        appId: prefs.getString(_appIdKey) ?? appId,
        token: token,
        pushkey: pushkey,
      );
    } catch (_) {
      return null;
    }
  }

  Future<int> _storedDropped() async {
    try {
      return (await SharedPreferences.getInstance()).getInt(_droppedKey) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _storeDropped(int count) async {
    try {
      await (await SharedPreferences.getInstance()).setInt(_droppedKey, count);
    } catch (e) {
      debugPrint('zuno/push: could not record the APNs drop count ($e)');
    }
  }

  Future<bool> _messageTone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return readNotificationSoundSettings(prefs).messageTone;
    } catch (_) {
      return NotificationSoundSettings.defaults.messageTone;
    }
  }

  Future<bool> _storedSound() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_soundKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> _storeSound(bool sound) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_soundKey, sound);
    } catch (e) {
      debugPrint('zuno/push: could not record the APNs pusher sound ($e)');
    }
  }

  Future<void> _remember(_Registration registration) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, registration.token);
      await prefs.setString(_appIdKey, registration.appId);
    } catch (e) {
      debugPrint('zuno/push: could not remember the APNs registration ($e)');
    }
  }
}

final apnsDeliveryProvider = ApnsDeliveryProvider();
