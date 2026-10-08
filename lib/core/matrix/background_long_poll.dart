import 'dart:async';

import 'package:matrix/matrix.dart';

const longPollTimeout = Duration(seconds: 90);
const shortPollTimeout = Duration(seconds: 30);

Duration nextPollTimeout(
  Duration current, {
  required bool failed,
  required Duration waited,
}) => failed && current > shortPollTimeout && waited >= shortPollTimeout
    ? shortPollTimeout
    : current;

class BackgroundLongPoll {
  BackgroundLongPoll(this._client, {this._now = DateTime.now});

  final Client _client;
  final DateTime Function() _now;
  var _timeout = longPollTimeout;
  var _running = false;
  var _generation = 0;

  bool get running => _running;

  void start() {
    if (_running) return;
    _running = true;
    _client.backgroundSync = false;
    unawaited(_loop(++_generation));
  }

  void stop() => _running = false;

  Future<void> _loop(int generation) async {
    while (_running && generation == _generation && _client.isLogged()) {
      var failed = false;
      final errors = _client.onSyncStatus.stream
          .where((update) => update.status == SyncStatus.error)
          .listen((_) => failed = true);
      final began = _now();
      try {
        await _client.oneShotSync(timeout: _timeout);
      } catch (_) {
        failed = true;
      } finally {
        unawaited(errors.cancel());
      }
      _timeout = nextPollTimeout(
        _timeout,
        failed: failed,
        waited: _now().difference(began),
      );
    }
  }
}
