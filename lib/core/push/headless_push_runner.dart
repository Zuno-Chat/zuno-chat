import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../calls/notifications/call_notification_service.dart';
import '../errors/best_effort.dart';
import '../errors/caught_errors.dart';
import '../matrix/client_lease.dart';
import '../notifications/notify_me.dart';
import 'incoming_push_handler.dart';
import 'push_timing.dart';
import 'push_wake_lock.dart';

const freshTokenBound = Duration(seconds: 10);

Future<void> initializeHeadlessNotifications() =>
    CallNotificationService.instance.initialize(claimDeclinePort: false);

Future<bool> prepareHeadlessPush({
  Future<void> Function() initializeNotifications =
      initializeHeadlessNotifications,
}) => runBestEffort(initializeNotifications, label: 'headless push setup');

class HeadlessPushRunner {
  Client? liveClient;

  Future<Client> Function()? clientBuilder;

  Future<void> Function(IncomingPushOutcome outcome)? onPushHandled;

  Future<void>? Function()? onRinging;

  void Function(Client client)? onClientOpened;

  Duration? idleLimit;

  String? Function() currentlyOpenRoomId = () => null;

  bool Function() isAppSyncing = () => false;

  Future<bool> Function() nativeAppInFront = () async => true;

  IncomingPushOutcome lastPushOutcome = IncomingPushOutcome.ignored;

  Future<void> _queue = Future<void>.value();
  Completer<void>? _callbackSignal;
  Future<Client>? _burst;
  Timer? _idle;
  int _queued = 0;
  bool _running = false;
  int _delivering = 0;
  int _needingClient = 0;
  bool _yieldAsked = false;
  final _held = <Future<void>>{};
  final _ringHolds = <Future<void>>{};
  final _closing = <Future<void>>{};

  bool get _usingClient =>
      _running || _queued > 0 || _needingClient > 0 || _held.isNotEmpty;

  bool get _inUse => _usingClient || _ringHolds.isNotEmpty;

  bool get quiescent =>
      _delivering == 0 && !_inUse && _burst == null && _closing.isEmpty;

  Future<bool> settle() async {
    if (_delivering > 0 || _inUse) return false;
    final burst = _burst;
    if (burst != null) _close(burst);
    await Future.wait(_closing.toList());
    return quiescent;
  }

  void yieldClient() {
    if (_burst == null) return;
    _yieldAsked = true;
    _afterUse();
  }

  StreamSubscription<void> yieldWhenAsked(Stream<void> requests) =>
      requests.listen((_) => yieldClient());

  void prepareClient() {
    if (liveClient != null || _burst != null) return;
    final build = clientBuilder;
    if (build == null) return;
    debugPrint('zuno/push: opening a client ahead of the push');
    _open(build);
  }

  Future<T?> withClient<T>(Future<T> Function(Client client) action) {
    final existing = liveClient;
    if (existing != null) return _withFreshToken(existing, action);
    final build = clientBuilder;
    if (build == null) return Future.value(null);
    _queued++;
    _idle?.cancel();
    return _enqueue(() async {
      _queued--;
      _running = true;
      try {
        final client = await (_burst ?? _open(build));
        return await _withFreshToken(client, action);
      } finally {
        _running = false;
        _afterUse();
      }
    });
  }

  void keepClientWhile(Future<void> work) => _hold(work, _held);

  void _hold(Future<void> work, Set<Future<void>> holds) {
    _idle?.cancel();
    final held = work.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) =>
          reportCaught('push client hold', error, stack),
    );
    holds.add(held);
    held.whenComplete(() {
      holds.remove(held);
      _afterUse();
    });
  }

  Future<T> _withFreshToken<T>(
    Client client,
    Future<T> Function(Client client) action,
  ) async {
    try {
      await client.ensureNotSoftLoggedOut().timeout(freshTokenBound);
    } on TimeoutException {
      debugPrint('zuno/push: token refresh still running, going on');
    }
    return action(client);
  }

  Future<Client> _open(Future<Client> Function() build) {
    debugPrint('zuno/push: opening a client for this push');
    final closed = Future.wait(_closing.toList());
    final burst = closed.then((_) => build());
    _burst = burst;
    burst.then(
      (client) {
        if (identical(_burst, burst)) _opened(client);
        _afterUse();
      },
      onError: (Object error) {
        if (!identical(_burst, burst)) return;
        _burst = null;
        _yieldAsked = false;
      },
    );
    return burst;
  }

  void _opened(Client client) {
    try {
      onClientOpened?.call(client);
    } catch (error, stack) {
      reportCaught('push client opened hook', error, stack);
    }
  }

  void _afterUse() {
    final burst = _burst;
    if (burst == null || _usingClient) return;
    if (_yieldAsked) {
      debugPrint('zuno/push: giving the client up for the app');
      _close(burst);
      return;
    }
    final limit = idleLimit;
    if (limit == null || _delivering > 0 || _inUse) return;
    _idle?.cancel();
    _idle = Timer(limit, () {
      _idle = null;
      if (identical(_burst, burst) && _delivering == 0 && !_inUse) {
        _close(burst);
      }
    });
  }

  void _close(Future<Client> burst) {
    _idle?.cancel();
    _idle = null;
    _yieldAsked = false;
    if (identical(_burst, burst)) _burst = null;
    debugPrint('zuno/push: letting the push client go');
    late final Future<void> closing;
    closing = burst
        .then((client) => client.dispose(closeDatabase: false))
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) =>
              reportCaught('push client close', error, stack),
        )
        .whenComplete(() => _closing.remove(closing));
    _closing.add(closing);
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> deliver(
    PushNotification notification, {
    bool? appInFront,
  }) async {
    _delivering++;
    _needingClient++;
    _idle?.cancel();
    var needsClient = true;
    void clientDone() {
      if (!needsClient) return;
      needsClient = false;
      _needingClient--;
      _afterUse();
    }

    try {
      lastPushOutcome = IncomingPushOutcome.ignored;
      if (isAppSyncing() && await _reallyInFront(appInFront)) {
        debugPrint('zuno/push: app is in front and syncing, leaving it');
        return;
      }
      if (notification.eventId == null) {
        clientDone();
        await _handleBadge(notification);
        return;
      }
      final timing = PushTiming(liveClient != null ? 'live' : 'headless');
      final outcome = await withClient((client) async {
        if (!client.isLogged()) {
          debugPrint('zuno/push: signed out, dropping push');
          await _retractNotice(notification);
          return IncomingPushOutcome.ignored;
        }
        timing.mark('client');
        final prefs = await SharedPreferences.getInstance();
        final handledAs = await handleIncomingPushNotification(
          client,
          notification,
          notifyMe: notifyMeFromPreferences(prefs),
          currentlyOpenRoomId: currentlyOpenRoomId(),
          timing: timing,
          onRefining: _keepRefining,
        );
        lastPushOutcome = handledAs;
        if (handledAs == IncomingPushOutcome.callRinging) _holdRing();
        return handledAs;
      });
      clientDone();
      timing.log();
      if (outcome == null) {
        debugPrint('zuno/push: no client, dropping push');
        return;
      }
      await onPushHandled?.call(outcome);
    } on ClientLeaseDenied {
      debugPrint('zuno/push: another client holds the store, notice kept');
    } catch (error, stack) {
      reportCaught('push handling', error, stack);
    } finally {
      clientDone();
      _delivering--;
      _afterUse();
      signalCallbackDone();
    }
  }

  void _holdRing() {
    final hold = onRinging?.call();
    if (hold != null) _hold(hold, _ringHolds);
  }

  void _keepRefining(Future<void> refinement) =>
      keepClientWhile(keepAwakeWhile(refinement));

  Future<void> _retractNotice(PushNotification notification) async {
    final roomId = notification.roomId;
    final eventId = notification.eventId;
    if (roomId == null || eventId == null) return;
    await CallNotificationService.instance.retractPushNotice(roomId, eventId);
  }

  Future<bool> _reallyInFront(bool? verdict) async {
    if (verdict != null) return verdict;
    try {
      return await nativeAppInFront();
    } catch (e, s) {
      reportCaught('push runner app in front check', e, s);
      return true;
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
