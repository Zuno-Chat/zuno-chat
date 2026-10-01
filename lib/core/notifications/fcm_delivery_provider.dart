import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, visibleForTesting;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../matrix/session_display_name.dart';
import '../push/fcm_bridge.dart';
import '../push/fcm_gateway.dart';
import '../push/fcm_pusher.dart';
import '../push/fcm_registration_store.dart';
import '../push/headless_push_runner.dart';
import '../push/pusher_reconciliation.dart';
import '../push/registration_retry.dart';
import 'notification_delivery_provider.dart';
import 'notification_permission.dart';

export '../push/registration_retry.dart'
    show defaultRegistrationRetryDelay, registrationRecheckInterval;

const fcmPendingTokenKey = 'push.fcm.pendingToken';

enum FcmStatus {
  idle,
  checkingPlayServices,
  playServicesUnavailable,
  playServicesUpdateRequired,
  playServicesDisabled,
  notConfigured,
  registering,
  tokenFailed,
  postingPusher,
  ready,
  pusherFailed,
}

class FcmDeliveryProvider implements NotificationDeliveryProvider {
  final _runner = HeadlessPushRunner();

  HeadlessPushRunner get runner => _runner;

  final status = ValueNotifier<FcmStatus>(FcmStatus.idle);

  String? lastPusherError;

  String? _token;
  String? get token => _token;

  bool get registered => _token != null;

  bool _deviceUnchecked = false;

  @visibleForTesting
  Future<FcmAvailability> Function() availabilityReader =
      FcmBridge.instance.availability;

  @visibleForTesting
  Future<FcmAvailability> Function() playServicesFixer =
      FcmBridge.instance.fixPlayServices;

  @visibleForTesting
  Future<String?> Function() tokenReader = FcmBridge.instance.getToken;

  @visibleForTesting
  Future<void> Function() tokenDeleter = FcmBridge.instance.deleteToken;

  @visibleForTesting
  Stream<String> Function() tokenRefreshStream = () =>
      FcmBridge.instance.tokenRefreshes;

  @visibleForTesting
  Future<bool> Function() notificationsAllowed = mayRegisterForNotifications;

  StreamSubscription<String>? _tokenRefreshSub;

  final _retry = RegistrationRetry();

  set retryDelay(Duration Function(int attempt) delay) => _retry.delay = delay;

  bool get retryScheduled => _retry.scheduled;

  final _recheck = RegistrationRecheck();

  set now(DateTime Function() value) => _recheck.now = value;

  @override
  Future<void> start(Client client) async {
    _runner.liveClient = client;
    if (status.value != FcmStatus.idle) return;
    if (!await notificationsAllowed()) return;
    await _restorePersistedRegistration(client);
    if (status.value != FcmStatus.idle) return;
    await registerNow(client);
  }

  Future<void> fixPlayServices(Client client) async {
    final blocked = _unavailableStatus(await playServicesFixer());
    if (blocked != null) {
      status.value = blocked;
      return;
    }
    _retry.cancel();
    await registerNow(client);
  }

  Future<void> retryIfFailed(Client client) async {
    if (status.value != FcmStatus.tokenFailed &&
        status.value != FcmStatus.pusherFailed) {
      return;
    }
    _retry.cancel();
    await registerNow(client);
  }

  Future<void> recheckRegistration(Client client) async {
    if (_blockedByDevice.contains(status.value)) {
      final availability = await availabilityReader();
      if (availability == FcmAvailability.unknown) return;
      final blocked = _unavailableStatus(availability);
      if (blocked != null) {
        status.value = blocked;
        return;
      }
      debugPrint('zuno/push: Google Play services is usable now, registering');
      await registerNow(client);
      return;
    }
    if (status.value != FcmStatus.ready || _token == null) return;
    if (_deviceUnchecked && await _deviceBlocked()) return;
    if (await _followCurrentToken(client)) return;
    final token = _token;
    if (token == null || !_recheck.claimDue()) return;
    final registered = await pusherIsRegistered(
      client,
      appId: fcmAppId,
      pushkey: token,
    );
    if (registered == false) {
      debugPrint('zuno/push: FCM pusher gone since last check, re-posting');
      await registerNow(client);
    }
  }

  Future<void> _restorePersistedRegistration(Client client) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = readFcmRegistration(prefs);
    if (stored == null) return;
    _token = stored;
    _deviceUnchecked = true;
    if (await _deviceBlocked()) return;
    lastPusherError = null;
    status.value = FcmStatus.ready;
    _recheck.markChecked();
    _listenForTokenRefresh(client);
    if (await _followCurrentToken(client)) return;

    final registered = await pusherIsRegistered(
      client,
      appId: fcmAppId,
      pushkey: stored,
    );
    if (registered == false) {
      debugPrint('zuno/push: FCM pusher gone from the homeserver, re-posting');
      await registerNow(client);
    }
  }

  Future<bool> _deviceBlocked() async {
    final availability = await availabilityReader();
    if (availability == FcmAvailability.unknown) return false;
    _deviceUnchecked = false;
    final blocked = _unavailableStatus(availability);
    if (blocked == null) return false;
    debugPrint(
      'zuno/push: FCM registration kept, but this device cannot use it '
      '(${blocked.name})',
    );
    status.value = blocked;
    return true;
  }

  Future<bool> _followCurrentToken(Client client) async {
    final prefs = await _reloadedPrefs();
    final moved = prefs == null ? null : readFcmRegistration(prefs);
    if (moved != null && _token != null) _token = moved;
    final pending = prefs == null ? null : _pendingToken(prefs);
    String? current;
    try {
      current = await tokenReader();
    } catch (e) {
      debugPrint(
        'zuno/push: FCM token check failed, keeping registration ($e)',
      );
    }
    final registered = _token;
    if (registered == null) return false;
    final wanted = (current == null || current.isEmpty) ? pending : current;
    if (wanted == null || wanted == registered) {
      if (pending != null) await _clearPendingToken();
      return false;
    }
    if (!await notificationsAllowed()) return false;
    final gatewayUrl = fcmGatewayUri(client.homeserver);
    if (gatewayUrl == null) return false;
    debugPrint('zuno/push: FCM token changed, moving the pusher to it');
    await _postPusher(client, token: wanted, gatewayUrl: gatewayUrl);
    return true;
  }

  Future<void> registerNow(Client client) async {
    _runner.liveClient = client;
    if (!await notificationsAllowed()) return;

    status.value = FcmStatus.checkingPlayServices;
    final availability = await availabilityReader();
    final blocked = _unavailableStatus(availability);
    if (blocked != null) {
      _retry.cancel();
      _deviceUnchecked = false;
      status.value = blocked;
      return;
    }
    _deviceUnchecked = availability == FcmAvailability.unknown;

    status.value = FcmStatus.registering;
    String? token;
    try {
      token = await tokenReader();
    } catch (e) {
      debugPrint('zuno/push: FCM token request failed ($e)');
      final permanent = e is FcmTokenException
          ? _permanentTokenFailure(e.failure)
          : null;
      if (permanent != null) {
        _retry.cancel();
        status.value = permanent;
        return;
      }
    }
    if (token == null || token.isEmpty) {
      status.value = FcmStatus.tokenFailed;
      _retry.schedule(() => registerNow(client));
      return;
    }

    status.value = FcmStatus.postingPusher;
    final gatewayUrl = fcmGatewayUri(client.homeserver);
    if (gatewayUrl == null) {
      lastPusherError = 'No server to send notifications through yet.';
      status.value = FcmStatus.pusherFailed;
      return;
    }
    if (await _postPusher(client, token: token, gatewayUrl: gatewayUrl)) {
      _listenForTokenRefresh(client);
    }
  }

  Future<bool> _postPusher(
    Client client, {
    required String token,
    required Uri gatewayUrl,
  }) async {
    final replaced = _token;
    try {
      await client.postPusher(
        buildFcmPusher(
          token: token,
          gatewayUrl: gatewayUrl,
          deviceDisplayName: sessionDisplayName(Platform.operatingSystem),
        ),
      );
    } catch (e) {
      lastPusherError = e.toString();
      status.value = FcmStatus.pusherFailed;
      _retry.schedule(() => registerNow(client));
      return false;
    }
    _token = token;
    lastPusherError = null;
    status.value = FcmStatus.ready;
    _recheck.markChecked();
    _retry.reset();
    await _rememberRegistration(token);
    await _clearPendingToken();
    if (replaced != null && replaced != token) {
      try {
        await client.deletePusher(fcmPusherId(replaced));
      } catch (e) {
        debugPrint('zuno/push: could not remove the replaced FCM pusher ($e)');
      }
    }
    return true;
  }

  Future<SharedPreferences?> _reloadedPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs;
    } catch (_) {
      return null;
    }
  }

  String? _pendingToken(SharedPreferences prefs) {
    final token = prefs.getString(fcmPendingTokenKey);
    return token == null || token.isEmpty ? null : token;
  }

  Future<void> _clearPendingToken() async {
    final prefs = await _reloadedPrefs();
    if (prefs == null || !prefs.containsKey(fcmPendingTokenKey)) return;
    try {
      await prefs.remove(fcmPendingTokenKey);
    } catch (e) {
      debugPrint('zuno/push: could not clear the pending FCM token ($e)');
    }
  }

  Future<void> _rememberRegistration(String token) async {
    try {
      await saveFcmRegistration(
        await SharedPreferences.getInstance(),
        token: token,
      );
    } catch (e) {
      debugPrint('zuno/push: could not remember the FCM registration ($e)');
    }
  }

  void _listenForTokenRefresh(Client client) {
    _tokenRefreshSub?.cancel();
    final Stream<String> refreshes;
    try {
      refreshes = tokenRefreshStream();
    } catch (e) {
      debugPrint('zuno/push: could not subscribe to token refresh ($e)');
      return;
    }
    _tokenRefreshSub = refreshes.listen((token) async {
      if (token == _token) return;
      if (!await notificationsAllowed()) return;
      final gatewayUrl = fcmGatewayUri(client.homeserver);
      if (gatewayUrl == null) return;
      await _postPusher(client, token: token, gatewayUrl: gatewayUrl);
    });
  }

  @override
  Future<void> stop(Client client) async {
    _retry.reset();
    final prefs = await _reloadedPrefs();
    final tokens = {
      ?_token,
      ?(prefs == null ? null : readFcmRegistration(prefs)),
    };
    if (tokens.isEmpty && status.value == FcmStatus.idle) return;
    _runner.liveClient = client;
    if (prefs != null) {
      try {
        await clearFcmRegistration(prefs);
        await prefs.remove(fcmPendingTokenKey);
      } catch (e) {
        debugPrint('zuno/push: could not forget the FCM registration ($e)');
      }
    }
    if (tokens.isNotEmpty) {
      String? failure;
      for (final token in tokens) {
        try {
          await client.deletePusher(fcmPusherId(token));
        } catch (e) {
          failure = 'Could not remove the push registration: $e';
        }
      }
      lastPusherError = failure;
      try {
        await tokenDeleter();
      } catch (e) {
        debugPrint('zuno/push: FCM token deletion failed ($e)');
      }
    }
    unawaited(_tokenRefreshSub?.cancel());
    _tokenRefreshSub = null;
    _token = null;
    _deviceUnchecked = false;
    status.value = FcmStatus.idle;
  }
}

const _blockedByDevice = {
  FcmStatus.playServicesUnavailable,
  FcmStatus.playServicesUpdateRequired,
  FcmStatus.playServicesDisabled,
};

FcmStatus? _unavailableStatus(FcmAvailability availability) =>
    switch (availability) {
      FcmAvailability.available || FcmAvailability.unknown => null,
      FcmAvailability.updateRequired => FcmStatus.playServicesUpdateRequired,
      FcmAvailability.disabled => FcmStatus.playServicesDisabled,
      FcmAvailability.unavailable => FcmStatus.playServicesUnavailable,
      FcmAvailability.notConfigured => FcmStatus.notConfigured,
    };

FcmStatus? _permanentTokenFailure(FcmTokenFailure failure) => switch (failure) {
  FcmTokenFailure.noPlayServices => FcmStatus.playServicesUnavailable,
  FcmTokenFailure.notConfigured => FcmStatus.notConfigured,
  FcmTokenFailure.unavailable || FcmTokenFailure.failed => null,
};

final fcmDeliveryProvider = FcmDeliveryProvider();
