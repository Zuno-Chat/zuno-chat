import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../calls/notifications/call_notification_service.dart';
import '../notifications/notify_me.dart';
import 'incoming_push_handler.dart';
import 'push_timing.dart';

Future<void> initializeHeadlessNotifications() =>
    CallNotificationService.instance.initialize(claimDeclinePort: false);

Future<bool> prepareHeadlessPush(
  HeadlessPushRunner runner, {
  Future<void> Function() initializeNotifications =
      initializeHeadlessNotifications,
}) async {
  runner.prepareClient();
  try {
    await initializeNotifications();
    return true;
  } catch (error, stack) {
    debugPrint('zuno/push: headless setup failed, push lost: $error\n$stack');
    return false;
  }
}

class HeadlessPushRunner {
  Client? liveClient;

  Future<Client> Function()? clientBuilder;

  Future<void> Function(IncomingPushOutcome outcome)? onPushHandled;

  String? Function() currentlyOpenRoomId = () => null;

  bool Function() isAppSyncing = () => false;

  IncomingPushOutcome lastPushOutcome = IncomingPushOutcome.ignored;

  Future<void> _queue = Future<void>.value();
  Completer<void>? _callbackSignal;
  Client? _burstClient;
  Future<Client>? _preparing;
  int _queued = 0;

  void prepareClient() {
    if (liveClient != null || _burstClient != null || _preparing != null) {
      return;
    }
    final build = clientBuilder;
    if (build == null) return;
    debugPrint('zuno/push: opening a client ahead of the push');
    _preparing = build()..ignore();
  }

  Future<T?> withClient<T>(Future<T> Function(Client client) action) {
    final existing = liveClient;
    if (existing != null) return _withFreshToken(existing, action);
    final build = clientBuilder;
    if (build == null) return Future.value(null);
    _queued++;
    return _enqueue(() async {
      _queued--;
      final client = await _openBurstClient(build);
      try {
        return await _withFreshToken(client, action);
      } finally {
        await _releaseBurstClient(client);
      }
    });
  }

  Future<T> _withFreshToken<T>(
    Client client,
    Future<T> Function(Client client) action,
  ) async {
    await client.ensureNotSoftLoggedOut();
    return action(client);
  }

  Future<Client> _openBurstClient(Future<Client> Function() build) async {
    final open = _burstClient;
    if (open != null) return open;
    final prepared = _preparing;
    _preparing = null;
    if (prepared != null) return _burstClient = await prepared;
    debugPrint('zuno/push: opening a client for this push');
    return _burstClient = await build();
  }

  Future<void> _discardPreparedClient() async {
    final prepared = _preparing;
    if (prepared == null || _queued > 0) return;
    _preparing = null;
    try {
      final client = await prepared;
      await client.dispose(closeDatabase: false);
    } catch (_) {}
  }

  Future<void> _releaseBurstClient(Client client) async {
    if (_queued > 0) {
      debugPrint('zuno/push: keeping the client, $_queued more queued');
      return;
    }
    _burstClient = null;
    debugPrint('zuno/push: releasing this push\'s client');
    await client.dispose(closeDatabase: false);
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> deliver(PushNotification notification) async {
    try {
      lastPushOutcome = IncomingPushOutcome.ignored;
      if (isAppSyncing()) {
        debugPrint('zuno/push: app is in front and syncing, leaving it');
        return;
      }
      if (notification.eventId == null) {
        await _handleBadge(notification);
        return;
      }
      final timing = PushTiming(liveClient != null ? 'live' : 'headless');
      final outcome = await withClient((client) async {
        timing.mark('client');
        final prefs = await SharedPreferences.getInstance();
        final handledAs = await handleIncomingPushNotification(
          client,
          notification,
          notifyMe: notifyMeFromPreferences(prefs),
          currentlyOpenRoomId: currentlyOpenRoomId(),
          timing: timing,
        );
        lastPushOutcome = handledAs;
        return handledAs;
      });
      timing.log();
      if (outcome == null) {
        debugPrint('zuno/push: no client, dropping push');
        return;
      }
      await onPushHandled?.call(outcome);
    } catch (error, stack) {
      debugPrint('zuno/push: handling failed: $error\n$stack');
    } finally {
      await _discardPreparedClient();
      signalCallbackDone();
    }
  }

  Future<void> _handleBadge(PushNotification notification) async {
    if (notification.counts?.unread == 0) {
      debugPrint('zuno/push: badge push says everything is read, clearing');
      await CallNotificationService.instance.cancelAllMessageNotifications();
    }
    lastPushOutcome = IncomingPushOutcome.badge;
    await onPushHandled?.call(IncomingPushOutcome.badge);
  }

  Future<void> waitForFirstCallback({
    Duration timeout = const Duration(seconds: 20),
  }) {
    final completer = Completer<void>();
    _callbackSignal = completer;
    return completer.future.timeout(timeout, onTimeout: () {});
  }

  void signalCallbackDone() {
    final completer = _callbackSignal;
    if (completer != null && !completer.isCompleted) completer.complete();
  }
}
