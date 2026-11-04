import 'dart:async';

import 'package:matrix/matrix.dart';

enum ConnectionStatus { online, noInternet, unreachable }

const noInternetDelay = Duration(seconds: 2);
const firstReprobeDelay = Duration(seconds: 2);
const maxReprobeDelay = Duration(seconds: 10);

bool isConnectionFailure(SyncStatusUpdate update) {
  final exception = update.error?.exception;
  return exception is SyncConnectionException || exception is TimeoutException;
}

class ConnectionMonitor {
  ConnectionMonitor({
    required Stream<bool> networkAvailable,
    required Stream<SyncStatusUpdate> syncStatus,
    required this._probe,
    this._foreground = true,
  }) {
    _subscriptions.addAll([
      networkAvailable.listen(_onNetworkAvailable),
      syncStatus.listen(_onSyncStatus),
    ]);
  }

  final Future<bool> Function() _probe;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _changes = StreamController<ConnectionStatus>.broadcast();

  ConnectionStatus _status = ConnectionStatus.online;
  bool _foreground;
  bool _network = true;
  bool _syncStartedWithoutNetwork = false;
  Timer? _noInternetTimer;
  Timer? _reprobeTimer;
  Duration _reprobeDelay = firstReprobeDelay;
  int _probeGeneration = 0;
  bool _probing = false;

  ConnectionStatus get status => _status;

  Stream<ConnectionStatus> get statuses => Stream.multi((controller) {
    controller.add(_status);
    final subscription = _changes.stream.listen(controller.add);
    controller.onCancel = subscription.cancel;
  });

  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (foreground) {
      _probeIfNotOnline();
    } else {
      _cancelProbe();
    }
  }

  Future<void> dispose() async {
    _cancelProbe();
    _cancelNoInternetTimer();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _changes.close();
  }

  void _onNetworkAvailable(bool available) {
    if (_network == available) return;
    _network = available;
    if (!available) {
      _syncStartedWithoutNetwork = false;
      _cancelProbe();
      _noInternetTimer = Timer(
        noInternetDelay,
        () => _setStatus(ConnectionStatus.noInternet),
      );
      return;
    }
    _cancelNoInternetTimer();
    _reprobeDelay = firstReprobeDelay;
    _probeIfNotOnline();
  }

  void _onSyncStatus(SyncStatusUpdate update) {
    switch (update.status) {
      case SyncStatus.waitingForResponse:
        if (!_network) _syncStartedWithoutNetwork = true;
      case SyncStatus.finished:
        _onHomeserverAnswered();
      case SyncStatus.error:
        if (isConnectionFailure(update)) {
          _onConnectionFailure();
        } else if (update.error?.exception is MatrixException) {
          _onHomeserverAnswered();
        }
      case SyncStatus.processing:
      case SyncStatus.cleaningUp:
        break;
    }
  }

  void _onHomeserverAnswered() {
    if (!_network) {
      if (!_syncStartedWithoutNetwork) return;
      _network = true;
      _cancelNoInternetTimer();
    }
    _cancelProbe();
    _reprobeDelay = firstReprobeDelay;
    _setStatus(ConnectionStatus.online);
  }

  void _onConnectionFailure() {
    if (!_network || !_foreground || _probing || _reprobeTimer != null) return;
    if (_status == ConnectionStatus.online) {
      unawaited(_probeNow());
    } else {
      _scheduleReprobe();
    }
  }

  void _probeIfNotOnline() {
    if (_foreground && _network && _status != ConnectionStatus.online) {
      unawaited(_probeNow());
    }
  }

  Future<void> _probeNow() async {
    _cancelProbe();
    final generation = _probeGeneration;
    _probing = true;
    final reachable = await _probe();
    if (generation != _probeGeneration) return;
    _probing = false;
    if (reachable) {
      _reprobeDelay = firstReprobeDelay;
      _setStatus(ConnectionStatus.online);
    } else {
      _setStatus(ConnectionStatus.unreachable);
      _scheduleReprobe();
    }
  }

  void _scheduleReprobe() {
    final delay = _reprobeDelay;
    final doubled = delay * 2;
    _reprobeDelay = doubled > maxReprobeDelay ? maxReprobeDelay : doubled;
    _reprobeTimer = Timer(delay, () {
      _reprobeTimer = null;
      unawaited(_probeNow());
    });
  }

  void _cancelProbe() {
    _probeGeneration++;
    _probing = false;
    _reprobeTimer?.cancel();
    _reprobeTimer = null;
  }

  void _cancelNoInternetTimer() {
    _noInternetTimer?.cancel();
    _noInternetTimer = null;
  }

  void _setStatus(ConnectionStatus status) {
    if (_status == status) return;
    _status = status;
    _changes.add(status);
  }
}
