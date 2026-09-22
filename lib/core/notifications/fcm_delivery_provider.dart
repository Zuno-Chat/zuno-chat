import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, visibleForTesting;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../matrix/session_display_name.dart';
import '../push/fcm_gateway.dart';
import '../push/fcm_pusher.dart';
import '../push/fcm_registration_store.dart';
import '../push/headless_push_runner.dart';
import '../push/play_services.dart';
import '../push/pusher_reconciliation.dart';
import '../push/registration_retry.dart';
import 'notification_delivery_provider.dart';

export '../push/registration_retry.dart'
    show defaultRegistrationRetryDelay, registrationRecheckInterval;

enum FcmStatus {
  idle,
  checkingPlayServices,
  playServicesUnavailable,
  playServicesUpdateRequired,
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

  @visibleForTesting
  Future<String?> Function() tokenReader = () =>
      FirebaseMessaging.instance.getToken();

  @visibleForTesting
  Future<void> Function() tokenDeleter = () =>
      FirebaseMessaging.instance.deleteToken();

  @visibleForTesting
  Stream<String> Function() tokenRefreshStream = () =>
      FirebaseMessaging.instance.onTokenRefresh;

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
    await _restorePersistedRegistration(client);
    if (status.value != FcmStatus.idle) return;
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
    final token = _token;
    if (status.value != FcmStatus.ready || token == null) return;
    if (!_recheck.claimDue()) return;
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
    lastPusherError = null;
    status.value = FcmStatus.ready;
    _recheck.markChecked();
    _listenForTokenRefresh(client);

    final String? current;
    try {
      current = await tokenReader();
    } catch (e) {
      debugPrint(
        'zuno/push: FCM token check failed, keeping registration ($e)',
      );
      return;
    }
    if (current != null && current.isNotEmpty && current != stored) {
      debugPrint('zuno/push: FCM token changed since last run, re-registering');
      await registerNow(client);
      return;
    }

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

  Future<void> registerNow(Client client) async {
    _runner.liveClient = client;

    status.value = FcmStatus.checkingPlayServices;
    switch (await PlayServicesProbe.instance.check()) {
      case PlayServicesAvailability.unavailable:
        status.value = FcmStatus.playServicesUnavailable;
        return;
      case PlayServicesAvailability.updateRequired:
        status.value = FcmStatus.playServicesUpdateRequired;
        return;
      case PlayServicesAvailability.available:
        break;
    }

    status.value = FcmStatus.registering;
    final String? token;
    try {
      token = await tokenReader();
    } catch (e) {
      debugPrint('zuno/push: FCM token request failed ($e)');
      status.value = FcmStatus.tokenFailed;
      _retry.schedule(() => registerNow(client));
      return;
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
    return true;
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
      final gatewayUrl = fcmGatewayUri(client.homeserver);
      if (gatewayUrl == null) return;
      await _postPusher(client, token: token, gatewayUrl: gatewayUrl);
    });
  }

  @override
  Future<void> stop(Client client) async {
    _retry.reset();
    final token = _token;
    if (token == null && status.value == FcmStatus.idle) return;
    _runner.liveClient = client;
    try {
      await clearFcmRegistration(await SharedPreferences.getInstance());
    } catch (e) {
      debugPrint('zuno/push: could not forget the FCM registration ($e)');
    }
    if (token != null) {
      try {
        await client.deletePusher(fcmPusherId(token));
        lastPusherError = null;
      } catch (e) {
        lastPusherError = 'Could not remove the push registration: $e';
      }
      try {
        await tokenDeleter();
      } catch (e) {
        debugPrint('zuno/push: FCM token deletion failed ($e)');
      }
    }
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _token = null;
    status.value = FcmStatus.idle;
  }
}

final fcmDeliveryProvider = FcmDeliveryProvider();
