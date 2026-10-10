import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:matrix/matrix.dart';

import 'sync_request_canceller.dart';

enum SyncReason { foreground, call, ring, liveShare, delivery }

enum SyncMode { off, live, background }

const _liveReasons = {SyncReason.foreground, SyncReason.call, SyncReason.ring};

SyncMode syncModeFor(
  Set<SyncReason> reasons, {
  required bool networkAvailable,
}) {
  if (reasons.any(_liveReasons.contains)) return SyncMode.live;
  if (reasons.isEmpty || !networkAvailable) return SyncMode.off;
  return SyncMode.background;
}

const _failuresBeforeBackoff = 3;
const _firstBackoff = Duration(seconds: 10);
const _maxBackoff = Duration(minutes: 5);

Duration? backgroundRetryDelay(int failures) {
  if (failures < _failuresBeforeBackoff) return null;
  final doublings = min(failures - _failuresBeforeBackoff, 16);
  final delay = _firstBackoff * pow(2, doublings);
  return delay > _maxBackoff ? _maxBackoff : delay;
}

const _livePoll = Duration(seconds: 30);
const _backgroundPoll = Duration(seconds: 90);
const _staleAfter = Duration(seconds: 15);

class SyncCoordinator {
  SyncCoordinator(this._client, this._requests) {
    _client.backgroundSync = false;
    _subscriptions.addAll([
      _client.onSync.stream.listen(
        (_) => _lastSync = clock.now(),
        onError: (_) {},
      ),
      _client.onLoginStateChanged.stream.listen(_onLoginState, onError: (_) {}),
    ]);
  }

  final Client _client;
  final SyncRequestCanceller _requests;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _reasons = <SyncReason>{};
  var _networkAvailable = true;
  var _mode = SyncMode.off;
  var _wentToBackground = false;
  var _longPollsCut = false;
  var _failures = 0;
  var _holds = 0;
  var _looping = false;
  var _disposed = false;
  var _cancelled = false;
  Completer<void>? _wake;
  DateTime? _lastSync;
  Future<void>? _catchUp;

  SyncMode get mode => _mode;

  Set<SyncReason> get reasons => Set.unmodifiable(_reasons);

  bool get syncing => _mode != SyncMode.off && _client.isLogged();

  void set(SyncReason reason, bool held) {
    if (held == _reasons.contains(reason)) return;
    if (held) {
      _reasons.add(reason);
      _failures = 0;
      _wakeUp();
    } else {
      _reasons.remove(reason);
    }
    if (reason == SyncReason.foreground) _onForeground(held);
    _apply();
  }

  void setNetworkAvailable(bool available) {
    if (available == _networkAvailable) return;
    _networkAvailable = available;
    if (available) {
      _failures = 0;
      _wakeUp();
      cancelWaitingRequest();
    }
    _apply();
  }

  void cancelWaitingRequest() {
    if (_requests.cancel()) _cancelled = true;
  }

  Future<void>? catchUp() {
    final running = _catchUp;
    if (running != null) return running;
    if (_holds > 0 || _client.syncPending) return null;
    final last = _lastSync;
    if (last != null && clock.now().difference(last) < _staleAfter) return null;
    debugPrint('zuno/push: the app\'s client is behind, catching up alongside');
    final catchUp = _catchUp = _client
        .oneShotSync(timeout: Duration.zero)
        .then<void>((_) {}, onError: (_) {});
    unawaited(catchUp.whenComplete(() => _catchUp = null));
    return catchUp;
  }

  Future<void> whileIdle(Future<void> Function() action) async {
    _holds++;
    _cancelled = true;
    _requests.pause();
    _wakeUp();
    try {
      while (_client.syncPending) {
        await _client.oneShotSync().then<void>((_) {}, onError: (_) {});
      }
      await action();
    } finally {
      _holds--;
      if (_holds == 0) _requests.resume();
      _apply();
    }
  }

  void dispose() {
    _disposed = true;
    _wakeUp();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
  }

  void _onForeground(bool held) {
    if (!held) {
      _wentToBackground = true;
      return;
    }
    if (!_wentToBackground) return;
    _wentToBackground = false;
    cancelWaitingRequest();
  }

  void _onLoginState(LoginState state) {
    _client.backgroundSync = false;
    if (state == LoginState.loggedIn) _apply();
  }

  bool get _shouldPoll =>
      !_disposed && _holds == 0 && _mode != SyncMode.off && _client.isLogged();

  Duration get _pollLength => _mode == SyncMode.background && !_longPollsCut
      ? _backgroundPoll
      : _livePoll;

  void _apply() {
    if (_disposed) return;
    final mode = syncModeFor(_reasons, networkAvailable: _networkAvailable);
    if (mode != _mode) {
      _mode = mode;
      final held = _reasons.map((reason) => reason.name).join(', ');
      Logs().i('zuno/sync: ${mode.name}${held.isEmpty ? '' : ' for $held'}');
      _wakeUp();
    }
    if (_shouldPoll && !_looping) unawaited(_loop());
  }

  Future<void> _loop() async {
    _looping = true;
    try {
      while (_shouldPoll) {
        final delay = _mode == SyncMode.background
            ? backgroundRetryDelay(_failures)
            : null;
        if (delay != null) await _sleep(delay);
        if (!_shouldPoll) break;
        await _round();
      }
    } finally {
      _looping = false;
    }
  }

  Future<void> _round() async {
    final length = _client.prevBatch == null ? null : _pollLength;
    final began = clock.now();
    final before = _client.onSyncStatus.value;
    _cancelled = false;
    var failed = false;
    try {
      await _client.oneShotSync(timeout: length);
    } catch (_) {
      failed = true;
    }
    final after = _client.onSyncStatus.value;
    failed |= !identical(after, before) && after?.status == SyncStatus.error;
    if (_cancelled) return;
    if (!failed) {
      _failures = 0;
      return;
    }
    if (_mode == SyncMode.background) _failures++;
    if (length == _backgroundPoll &&
        clock.now().difference(began) >= _livePoll) {
      _longPollsCut = true;
    }
  }

  Future<void> _sleep(Duration delay) {
    final wake = _wake = Completer<void>();
    final timer = Timer(delay, _wakeUp);
    return wake.future.whenComplete(timer.cancel);
  }

  void _wakeUp() {
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }
}
