import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:matrix/matrix.dart';

import '../../calls/notifications/call_notification_service.dart';
import '../../calls/notifications/ring_from_push.dart';
import '../../calls/notifications/server_ring.dart';
import '../../calls/platform/incoming_call_presenter.dart';
import '../../errors/best_effort.dart';
import '../../errors/caught_errors.dart';
import '../../matrix/client_lease.dart';
import '../../notifications/messages/message_notifications.dart';
import '../../notifications/settings/notify_me.dart';
import '../../platform/platform_capabilities.dart';
import 'incoming_push_handler.dart';
import 'push_timing.dart';
import 'push_wake_lock.dart';

Future<void> initializeHeadlessNotifications() =>
    CallNotificationService.instance.initialize(claimLiveRoutes: false);

Future<bool> prepareHeadlessPush({
  Future<void> Function() initializeNotifications =
      initializeHeadlessNotifications,
}) => runBestEffort(initializeNotifications, label: 'headless push setup');

void startHeadlessCrashReporting(Future<void> Function() start) =>
    unawaited(runBestEffort(start, label: 'headless crash reporting start'));

class HeadlessPushRunner {
  Client? liveClient;

  Future<Client> Function()? clientBuilder;

  Future<void>? Function()? onRinging;

  void Function(Client client)? onClientOpened;

  Duration? idleLimit;

  String? Function() currentlyOpenRoomId = () => null;

  bool Function() isAppSyncing = () => false;

  void Function(ServerRing ring) ringInApp = (_) {};

  Future<bool> Function() nativeAppInFront = () async => true;

  IncomingPushOutcome lastPushOutcome = IncomingPushOutcome.ignored;

  Future<void> _queue = Future<void>.value();
  Completer<void> _appWantsClient = Completer<void>();
  Completer<void>? _callbackSignal;
  Future<Client>? _burst;
  Timer? _idle;
  int _queued = 0;
  bool _running = false;
  int _delivering = 0;
  int _needingClient = 0;
  final _held = <Future<void>>{};
  final _ringHolds = <Future<void>>{};
  final _closing = <Future<void>>{};

  bool get _usingClient =>
      _running || _queued > 0 || _needingClient > 0 || _held.isNotEmpty;

  bool get _inUse => _usingClient || _ringHolds.isNotEmpty;

  Future<void> get heldWorkDone async {
    while (_held.isNotEmpty || _ringHolds.isNotEmpty) {
      await Future.wait([..._held, ..._ringHolds]);
    }
  }

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
    if (!_appWantsClient.isCompleted) _appWantsClient.complete();
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
    if (existing != null) return _withReadyClient(existing, action);
    final build = clientBuilder;
    if (build == null) return Future.value(null);
    _queued++;
    _idle?.cancel();
    // shortcut: a burst client handles whole pushes one at a time, so a UnifiedPush backlog posts one by one, upgrade by queueing only the client's opening and closing
    return _enqueue(() async {
      _queued--;
      _running = true;
      try {
        final client = await (_burst ?? _open(build));
        return await _withReadyClient(client, action);
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

  Future<T> _withReadyClient<T>(
    Client client,
    Future<T> Function(Client client) action,
  ) async {
    await Future.wait<void>([
      client.ensureNotSoftLoggedOut(),
      ?client.userDeviceKeysLoading,
      ?client.roomsLoading,
      ?client.accountDataLoading,
    ]);
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
        _appWantsClient = Completer<void>();
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
    if (_appWantsClient.isCompleted) {
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
    _appWantsClient = Completer<void>();
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

  Future<void> deliver(PushNotification notification, {bool? appInFront}) =>
      _deliverWith(appInFront, () async {
        if (notification.eventId == null) {
          await _handleBadge(notification);
          return;
        }
        final live = liveClient != null;
        final timing = PushTiming(live ? 'live' : 'headless');
        final outcome = await withClient((client) async {
          if (!client.isLogged()) {
            debugPrint('zuno/push: signed out, dropping push');
            await _retractNotice(notification);
            return IncomingPushOutcome.ignored;
          }
          timing.mark('client');
          return handleIncomingPushNotification(
            client,
            notification,
            notifyMe: await currentNotifyMe(),
            currentlyOpenRoomId: currentlyOpenRoomId(),
            timing: timing,
            onRefining: _keepRefining,
            onRinging: _holdRing,
            appWantsClient: live ? null : _appWantsClient.future,
          );
        });
        timing.log();
        if (outcome == null) {
          debugPrint('zuno/push: no client, dropping push');
          return;
        }
        lastPushOutcome = outcome;
      });

  Future<void> deliverRing(ServerRing ring) =>
      _deliverWith(ring.appInFront, inFront: () => ringInApp(ring), () async {
        final presenter = incomingCallPresenterFor(ambientCapabilities);
        final rang = await withClient((client) async {
          final call = client.isLogged()
              ? incomingCallFromServerRing(client, ring)
              : null;
          if (call != null) return ringFromPush(call, presenter);
          await presenter.cancelIncoming(
            roomId: ring.roomId,
            callId: ring.callId,
          );
          return false;
        });
        if (rang != true) return;
        lastPushOutcome = IncomingPushOutcome.callRinging;
        _holdRing();
      });

  Future<void> _deliverWith(
    bool? appInFront,
    Future<void> Function() handle, {
    void Function()? inFront,
  }) async {
    _delivering++;
    _needingClient++;
    _idle?.cancel();
    try {
      lastPushOutcome = IncomingPushOutcome.ignored;
      if (isAppSyncing() && await _reallyInFront(appInFront)) {
        debugPrint('zuno/push: app is in front and syncing, leaving it');
        inFront?.call();
        return;
      }
      await handle();
    } on ClientLeaseDenied {
      debugPrint('zuno/push: another client holds the store, notice kept');
    } catch (error, stack) {
      reportCaught('push handling', error, stack);
    } finally {
      _needingClient--;
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
    await MessageNotifications.instance.retractPushNotice(roomId, eventId);
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
      await MessageNotifications.instance.cancelAllMessageNotifications();
    }
    lastPushOutcome = IncomingPushOutcome.badge;
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
