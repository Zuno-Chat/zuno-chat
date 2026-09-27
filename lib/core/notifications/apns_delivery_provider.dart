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

class ApnsDeliveryProvider implements NotificationDeliveryProvider {
  ApnsDeliveryProvider({PlatformCapabilities? capabilities})
    : _injectedCapabilities = capabilities;

  final PlatformCapabilities? _injectedCapabilities;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  final status = ValueNotifier<ApnsStatus>(ApnsStatus.idle);

  String? lastPusherError;

  String? _token;
  String? get token => _token;

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
    final stored = await _storedToken();
    if (stored == null) {
      await registerNow(client);
      return;
    }
    _token = stored;
    lastPusherError = null;
    status.value = ApnsStatus.ready;
    _recheck.markChecked();

    final String? current;
    try {
      current = await tokenReader();
    } catch (e) {
      debugPrint(
        'zuno/push: APNs token check failed, keeping registration ($e)',
      );
      return;
    }
    if (current != null && current.isNotEmpty && current != stored) {
      await registerNow(client);
      return;
    }
    final registered = await pusherIsRegistered(
      client,
      appId: apnsAppId,
      pushkey: stored,
    );
    if (registered == false) await registerNow(client);
  }

  Future<void> retryIfFailed(Client client) async {
    if (status.value != ApnsStatus.tokenFailed &&
        status.value != ApnsStatus.pusherFailed) {
      return;
    }
    _retry.cancel();
    await registerNow(client);
  }

  Future<void> recheckRegistration(Client client) async {
    final token = _token;
    if (status.value != ApnsStatus.ready || token == null) return;
    if (!_recheck.claimDue()) return;
    final registered = await pusherIsRegistered(
      client,
      appId: apnsAppId,
      pushkey: token,
    );
    if (registered == false) await registerNow(client);
  }

  Future<void> registerNow(Client client) async {
    if (!_capabilities.apnsRegistration) return;
    if (!await notificationsAllowed()) return;

    status.value = ApnsStatus.registering;
    final String? token;
    try {
      token = await tokenReader();
    } catch (e) {
      debugPrint('zuno/push: APNs token request failed ($e)');
      status.value = ApnsStatus.tokenFailed;
      _retry.schedule(() => registerNow(client));
      return;
    }
    if (token == null || token.isEmpty) {
      status.value = ApnsStatus.tokenFailed;
      _retry.schedule(() => registerNow(client));
      return;
    }

    status.value = ApnsStatus.postingPusher;
    final gatewayUrl = fcmGatewayUri(client.homeserver);
    if (gatewayUrl == null) {
      lastPusherError = 'No server to send notifications through yet.';
      status.value = ApnsStatus.pusherFailed;
      return;
    }
    try {
      await client.postPusher(
        buildApnsPusher(
          token: token,
          gatewayUrl: gatewayUrl,
          deviceDisplayName: sessionDisplayName('ios'),
        ),
      );
    } catch (e) {
      lastPusherError = e.toString();
      status.value = ApnsStatus.pusherFailed;
      _retry.schedule(() => registerNow(client));
      return;
    }
    _token = token;
    lastPusherError = null;
    status.value = ApnsStatus.ready;
    _recheck.markChecked();
    _retry.reset();
    await _rememberToken(token);
  }

  @override
  Future<void> stop(Client client) async {
    _retry.reset();
    final token = _token ?? await _storedToken();
    if (token == null && status.value == ApnsStatus.idle) return;
    try {
      await (await SharedPreferences.getInstance()).remove(_tokenKey);
    } catch (e) {
      debugPrint('zuno/push: could not forget the APNs registration ($e)');
    }
    if (token != null) {
      try {
        await client.deletePusher(apnsPusherId(token));
        lastPusherError = null;
      } catch (e) {
        lastPusherError = 'Could not remove the push registration: $e';
      }
    }
    _token = null;
    status.value = ApnsStatus.idle;
  }

  Future<String?> _storedToken() async {
    try {
      final stored = (await SharedPreferences.getInstance()).getString(
        _tokenKey,
      );
      return stored == null || stored.isEmpty ? null : stored;
    } catch (_) {
      return null;
    }
  }

  Future<void> _rememberToken(String token) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_tokenKey, token);
    } catch (e) {
      debugPrint('zuno/push: could not remember the APNs registration ($e)');
    }
  }
}

final apnsDeliveryProvider = ApnsDeliveryProvider();
