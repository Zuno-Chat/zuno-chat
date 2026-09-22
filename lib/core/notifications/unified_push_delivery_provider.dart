import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush/unifiedpush.dart';
import 'package:unifiedpush_platform_interface/data/public_key_set.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart'
    show UnifiedPushPlatform;

import '../matrix/session_display_name.dart';
import '../push/fcm_gateway.dart';
import '../push/headless_push_runner.dart';
import '../push/incoming_push_handler.dart';
import '../push/matrix_unified_push_gateway.dart';
import '../push/push_notification_codec.dart';
import '../push/pusher_reconciliation.dart';
import '../push/registration_retry.dart';
import '../push/unified_push_pusher.dart';
import '../push/unified_push_registration_store.dart';
import 'background_sync_service.dart';
import 'notification_delivery_provider.dart';

export '../push/registration_retry.dart' show registrationRecheckInterval;
export '../push/unified_push_pusher.dart' show unifiedPushViaHomeserverGateway;

enum UnifiedPushStatus {
  idle,
  findingDistributor,
  noDistributorFound,
  distributorSelected,
  registering,
  postingPusher,
  ready,
  registrationFailed,
  pusherFailed,
}

class UnifiedPushDeliveryProvider implements NotificationDeliveryProvider {
  final _runner = HeadlessPushRunner();

  Uri? _endpointUrl;
  Uri? _gatewayUrl;
  String? _pushkey;
  Pusher? _pendingPusher;
  bool _callbacksRegistered = false;
  bool _active = false;

  final status = ValueNotifier<UnifiedPushStatus>(UnifiedPushStatus.idle);

  final distributorBatteryRestricted = ValueNotifier<bool>(false);

  Future<bool> Function(String package) distributorIgnoresBatteryOptimizations =
      BackgroundSyncService.instance.isPackageIgnoringBatteryOptimizations;

  FailedReason? lastFailureReason;

  String? lastPusherError;

  String? savedDistributor;

  final _retry = RegistrationRetry();

  set retryDelay(Duration Function(int attempt) delay) => _retry.delay = delay;

  bool get retryScheduled => _retry.scheduled;

  final _recheck = RegistrationRecheck();

  set now(DateTime Function() value) => _recheck.now = value;

  Uri? get gatewayUrl => _gatewayUrl;

  Uri? get endpointUrl => _endpointUrl;

  Future<void> ensureCallbacksRegistered(Client client) async {
    _runner.liveClient = client;
    await _initializePlugin();
  }

  Future<void> ensureHeadlessCallbacksRegistered({
    required Future<Client> Function() clientBuilder,
    required Future<void> Function(IncomingPushOutcome outcome) onPushHandled,
  }) async {
    _runner.clientBuilder = clientBuilder;
    _runner.onPushHandled = onPushHandled;
    await _initializePlugin();
  }

  Future<void> _initializePlugin() async {
    if (_callbacksRegistered) return;
    _callbacksRegistered = true;
    try {
      await UnifiedPushPlatform.instance.initializeCallback(
        onNewEndpoint: (endpoint, instance) =>
            _onNewEndpoint(endpoint, instance),
        onRegistrationFailed: (reason, instance) =>
            _onRegistrationFailed(reason, instance),
        onUnregistered: (instance) => _onUnregistered(instance),
        onMessage: (message, instance) => _onMessage(message, instance),
      );
    } catch (e) {
      _callbacksRegistered = false;
      debugPrint('zuno/push: UnifiedPush callbacks not registered ($e)');
    }
  }

  http.Client Function() gatewayHttpClient = http.Client.new;

  Future<T?> withClient<T>(Future<T> Function(Client client) action) =>
      _runner.withClient(action);

  HeadlessPushRunner get runner => _runner;

  Future<void> waitForFirstCallback({
    Duration timeout = const Duration(seconds: 20),
  }) => _runner.waitForFirstCallback(timeout: timeout);

  @override
  Future<void> start(Client client) async {
    _active = true;
    await ensureCallbacksRegistered(client);
    await _restorePersistedRegistration(client);
    await _autoRegisterAvailableDistributor(client);
    await refreshDistributorBattery();
  }

  Future<void> retryIfFailed(Client client) async {
    _runner.liveClient = client;
    switch (status.value) {
      case UnifiedPushStatus.registrationFailed:
        _retry.cancel();
        await _registerWithSavedDistributor();
      case UnifiedPushStatus.pusherFailed:
        _retry.cancel();
        await _postPendingPusher(client);
      default:
        return;
    }
  }

  Future<void> recheckRegistration(Client client) async {
    await refreshDistributorBattery();
    final pushkey = _pushkey;
    if (status.value != UnifiedPushStatus.ready || pushkey == null) return;
    if (!_recheck.claimDue()) return;
    final registered = await pusherIsRegistered(
      client,
      appId: unifiedPushAppId,
      pushkey: pushkey,
    );
    if (registered == false) {
      debugPrint('zuno/push: UnifiedPush pusher gone since last check');
      final stored = readUnifiedPushRegistration(
        await SharedPreferences.getInstance(),
      );
      if (stored != null) await _repostStoredPusher(client, stored);
    }
  }

  Future<void> refreshDistributorBattery() async {
    try {
      final distributor = await knownDistributor();
      if (distributor == null) {
        distributorBatteryRestricted.value = false;
        return;
      }
      distributorBatteryRestricted.value =
          !await distributorIgnoresBatteryOptimizations(distributor);
    } catch (e) {
      debugPrint('zuno/push: distributor battery check failed ($e)');
    }
  }

  Future<void> _autoRegisterAvailableDistributor(Client client) async {
    _runner.liveClient = client;
    await discoverDistributorsIfNeeded();
    if (status.value != UnifiedPushStatus.distributorSelected) return;
    await _registerWithSavedDistributor();
  }

  Future<void> _restorePersistedRegistration(Client client) async {
    if (status.value != UnifiedPushStatus.idle) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = readUnifiedPushRegistration(prefs);
    if (stored == null) return;
    _endpointUrl = stored.endpointUrl;
    _gatewayUrl = stored.gatewayUrl;
    _pushkey = stored.effectivePushkey;
    savedDistributor = await UnifiedPush.getDistributor();
    status.value = UnifiedPushStatus.ready;
    _recheck.markChecked();

    final registered = await pusherIsRegistered(
      client,
      appId: unifiedPushAppId,
      pushkey: stored.effectivePushkey,
    );
    if (registered == false) {
      debugPrint(
        'zuno/push: UnifiedPush pusher gone from the homeserver, re-posting',
      );
      await _repostStoredPusher(client, stored);
    }
  }

  Future<void> _repostStoredPusher(
    Client client,
    UnifiedPushRegistration stored,
  ) async {
    final auth = stored.auth;
    _pendingPusher = await _buildPusher(
      endpointUrl: stored.endpointUrl,
      keys: stored.pushkey.isEmpty || auth == null
          ? null
          : PublicKeySet(stored.pushkey, auth),
      homeserverGateway: fcmGatewayUri(client.homeserver),
      knownGatewayUrl: stored.gatewayUrl,
    );
    await _postPendingPusher(client);
  }

  Future<Pusher> _buildPusher({
    required Uri endpointUrl,
    required PublicKeySet? keys,
    required Uri? homeserverGateway,
    Uri? knownGatewayUrl,
  }) async {
    if (keys != null && homeserverGateway != null) {
      return buildUnifiedPushWebPusher(
        endpointUrl: endpointUrl,
        keys: keys,
        gatewayUrl: homeserverGateway,
        deviceDisplayName: sessionDisplayName(Platform.operatingSystem),
      );
    }
    final gatewayUrl =
        knownGatewayUrl ??
        await resolveMatrixGatewayUrl(
          endpointUrl,
          httpClient: gatewayHttpClient(),
        );
    return buildUnifiedPushPusher(
      endpointUrl: endpointUrl,
      gatewayUrl: gatewayUrl,
      deviceDisplayName: sessionDisplayName(Platform.operatingSystem),
    );
  }

  Future<void> discoverDistributors() async {
    status.value = UnifiedPushStatus.findingDistributor;
    if (await UnifiedPush.tryUseCurrentOrDefaultDistributor()) {
      final chosen = await UnifiedPush.getDistributor();
      if (chosen != null) {
        savedDistributor = chosen;
        status.value = UnifiedPushStatus.distributorSelected;
        return;
      }
    }
    final installed = await UnifiedPush.getDistributors();
    if (installed.isEmpty) {
      savedDistributor = null;
      status.value = UnifiedPushStatus.noDistributorFound;
      return;
    }
    await _saveDistributor(installed.first);
  }

  Future<void> discoverDistributorsIfNeeded() async {
    if (status.value != UnifiedPushStatus.idle) return;
    final known = await knownDistributor();
    if (known == null) {
      await discoverDistributors();
      return;
    }
    savedDistributor = known;
    status.value = UnifiedPushStatus.distributorSelected;
  }

  Future<void> removeRegistration(Client client) async {
    _retry.reset();
    final pushkey = _pushkey ?? _endpointUrl?.toString();
    if (pushkey != null) {
      try {
        await client.deletePusher(unifiedPushPusherIdFor(pushkey));
      } catch (_) {}
    }
    await UnifiedPush.unregister();
    await clearUnifiedPushRegistration(await SharedPreferences.getInstance());
    _endpointUrl = null;
    _gatewayUrl = null;
    _pushkey = null;
    _pendingPusher = null;
    savedDistributor = null;
    lastPusherError = null;
    status.value = UnifiedPushStatus.idle;
  }

  Future<void> _saveDistributor(String distributor) async {
    await UnifiedPush.saveDistributor(distributor);
    savedDistributor = distributor;
    status.value = UnifiedPushStatus.distributorSelected;
  }

  Future<String?> knownDistributor() async =>
      await UnifiedPush.getDistributor() ?? savedDistributor;

  Future<void> registerNow(Client client) async {
    _runner.liveClient = client;
    await ensureCallbacksRegistered(client);
    if (await knownDistributor() == null) {
      await discoverDistributors();
      if (status.value != UnifiedPushStatus.distributorSelected) return;
    }
    await _registerWithSavedDistributor();
    await refreshDistributorBattery();
  }

  Future<void> _registerWithSavedDistributor() async {
    status.value = UnifiedPushStatus.registering;
    await UnifiedPush.register(
      messageForDistributor: 'Zuno wants to receive notifications',
    );
  }

  @override
  Future<void> stop(Client client) async {
    _retry.reset();
    final prefs = await SharedPreferences.getInstance();
    final persisted = readUnifiedPushRegistration(prefs);
    if (!_active && persisted == null) return;
    _active = false;
    _runner.liveClient = client;
    final pushkey = _pushkey ?? persisted?.effectivePushkey;
    _endpointUrl = null;
    _gatewayUrl = null;
    _pushkey = null;
    _pendingPusher = null;
    if (pushkey != null) {
      try {
        await client.deletePusher(unifiedPushPusherIdFor(pushkey));
        lastPusherError = null;
      } catch (e) {
        lastPusherError = 'Could not remove the push registration: $e';
      }
    }
    await UnifiedPush.unregister();
    await clearUnifiedPushRegistration(prefs);
    savedDistributor = null;
    distributorBatteryRestricted.value = false;
    status.value = UnifiedPushStatus.idle;
  }

  Future<void> _onNewEndpoint(PushEndpoint endpoint, String instance) async {
    debugPrint('zuno/push: new endpoint');
    try {
      await _runner.withClient((client) async {
        final endpointUrl = Uri.parse(endpoint.url);
        _endpointUrl = endpointUrl;
        status.value = UnifiedPushStatus.postingPusher;
        final pusher = await _buildPusher(
          endpointUrl: endpointUrl,
          keys: unifiedPushViaHomeserverGateway ? endpoint.pubKeySet : null,
          homeserverGateway: fcmGatewayUri(client.homeserver),
        );
        _gatewayUrl = pusher.data.url;
        _pendingPusher = pusher;
        await _postPendingPusher(client);
      });
    } finally {
      _runner.signalCallbackDone();
    }
  }

  Future<void> _postPendingPusher(Client client) async {
    final pusher = _pendingPusher;
    final endpointUrl = _endpointUrl;
    if (pusher == null || endpointUrl == null) return;
    status.value = UnifiedPushStatus.postingPusher;
    try {
      await client.postPusher(pusher);
    } catch (e) {
      lastPusherError = e.toString();
      status.value = UnifiedPushStatus.pusherFailed;
      _retry.schedule(() => _retryWithLiveClient());
      return;
    }
    _pushkey = pusher.pushkey;
    lastPusherError = null;
    _retry.reset();
    _recheck.markChecked();
    await saveUnifiedPushRegistration(
      await SharedPreferences.getInstance(),
      endpointUrl: endpointUrl,
      gatewayUrl: _gatewayUrl,
      pushkey: pusher.pushkey,
      auth: pusher.data.additionalProperties['auth'] as String?,
    );
    status.value = UnifiedPushStatus.ready;
  }

  Future<void> _retryWithLiveClient() async {
    final client = _runner.liveClient;
    if (client == null) return;
    await retryIfFailed(client);
  }

  void _onRegistrationFailed(FailedReason reason, String instance) {
    lastFailureReason = reason;
    status.value = UnifiedPushStatus.registrationFailed;
    if (reason == FailedReason.network ||
        reason == FailedReason.internalError) {
      _retry.schedule(() => _retryWithLiveClient());
    }
    _runner.signalCallbackDone();
  }

  void _onUnregistered(String instance) {
    _endpointUrl = null;
    _gatewayUrl = null;
    _pushkey = null;
    _pendingPusher = null;
    savedDistributor = null;
    status.value = UnifiedPushStatus.idle;
    unawaited(
      SharedPreferences.getInstance().then(clearUnifiedPushRegistration),
    );
    _runner.signalCallbackDone();
  }

  IncomingPushOutcome get lastPushOutcome => _runner.lastPushOutcome;

  @visibleForTesting
  Future<void> deliverPushForTest(PushMessage message) =>
      _onMessage(message, 'default');

  Future<void> _onMessage(PushMessage message, String instance) async {
    debugPrint('zuno/push: push received (${message.content.length} bytes)');
    final notification = pushNotificationFromMessageBytes(message.content);
    if (notification == null) {
      debugPrint('zuno/push: push payload could not be decoded');
      _runner.signalCallbackDone();
      return;
    }
    await _runner.deliver(notification);
  }
}
