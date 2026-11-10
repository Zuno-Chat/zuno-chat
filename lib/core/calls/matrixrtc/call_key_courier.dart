import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:matrix/matrix.dart';

import '../../errors/backoff.dart';
import '../../errors/caught_errors.dart';
import '../../matrix/database/ephemeral_to_device.dart';
import '../models/voip_participant_id.dart';
import 'call_sender_key_event.dart';

class CallKeyCourier {
  CallKeyCourier(
    this._client, {
    required this.callId,
    required this.baseDelay,
    required this.maxDelay,
    required this.stopped,
  });

  final Client _client;
  final String callId;
  final Duration baseDelay;
  final Duration maxDelay;
  final bool Function() stopped;

  static const _reportAfter = 3;

  final Map<VoipParticipantId, _Delivery> _inFlight = {};
  final Map<VoipParticipantId, SenderKeyMark> _delivered = {};

  bool refuses(VoipParticipantId id) {
    final list = _client.userDeviceKeys[id.userId];
    if (list == null || list.outdated) return false;
    return !(list.deviceKeys[id.deviceId]?.encryptToDevice ?? false);
  }

  bool send(
    Iterable<VoipParticipantId> ids,
    SenderKey key, {
    bool resend = false,
  }) {
    if (stopped()) return false;
    final mark = markOf(key);
    final group = <VoipParticipantId, _Delivery>{};
    for (final id in ids) {
      if (refuses(id)) continue;
      if (!resend && (_delivered[id] == mark || _inFlight[id]?.mark == mark)) {
        continue;
      }
      _inFlight.remove(id)?.stop();
      group[id] = _inFlight[id] = _Delivery(mark);
    }
    if (group.isEmpty) return false;
    final content = buildSenderKeyContent(callId: callId, key: key);
    unawaited(_attempt(group, content, 1));
    return true;
  }

  bool forget(VoipParticipantId id) {
    final inFlight = _inFlight.remove(id)?..stop();
    return _delivered.remove(id) != null || inFlight != null;
  }

  void stopAll() {
    for (final delivery in _inFlight.values) {
      delivery.stop();
    }
    _inFlight.clear();
  }

  bool _current(VoipParticipantId id, _Delivery delivery) =>
      !stopped() && identical(_inFlight[id], delivery);

  Future<void> _attempt(
    Map<VoipParticipantId, _Delivery> group,
    Map<String, Object?> content,
    int n,
  ) async {
    final live = {
      for (final MapEntry(key: id, value: delivery) in group.entries)
        if (_current(id, delivery)) id: delivery,
    };
    if (live.isEmpty) return;
    final Map<VoipParticipantId, DeviceKeys> devices;
    try {
      devices = await _devicesOf(live.keys);
    } catch (e, s) {
      _retryAll(live, content, n, e, s);
      return;
    }
    final sendable = <VoipParticipantId, DeviceKeys>{};
    for (final MapEntry(key: id, value: delivery) in live.entries) {
      if (!_current(id, delivery)) continue;
      switch (devices[id]) {
        case null:
          _retry(id, delivery, content, n, StateError('No device keys yet'));
        case final device when !device.encryptToDevice:
          _inFlight.remove(id);
        case final device:
          sendable[id] = device;
      }
    }
    if (sendable.isEmpty) return;
    final List<DeviceKeys> unreached;
    try {
      unreached = await sendEphemeralToDevice(
        _client,
        sendable.values.toList(),
        callSenderKeyEventType,
        content,
      );
    } catch (e, s) {
      _retryAll(
        {for (final id in sendable.keys) id: live[id]!},
        content,
        n,
        e,
        s,
      );
      return;
    }
    for (final MapEntry(key: id, value: device) in sendable.entries) {
      final delivery = live[id]!;
      if (!identical(_inFlight[id], delivery)) continue;
      if (unreached.contains(device)) {
        _retry(
          id,
          delivery,
          content,
          n,
          StateError('No Olm session with the device yet'),
        );
      } else {
        _inFlight.remove(id);
        _delivered[id] = delivery.mark;
      }
    }
  }

  void _retryAll(
    Map<VoipParticipantId, _Delivery> group,
    Map<String, Object?> content,
    int n,
    Object error,
    StackTrace stack,
  ) {
    for (final MapEntry(key: id, value: delivery) in group.entries) {
      _retry(id, delivery, content, n, error, stack);
    }
  }

  void _retry(
    VoipParticipantId id,
    _Delivery delivery,
    Map<String, Object?> content,
    int n,
    Object error, [
    StackTrace? stack,
  ]) {
    if (!_current(id, delivery)) return;
    if (n == _reportAfter) reportCaught('deliver our sender key', error, stack);
    final delay = backoffDelay(n, baseDelay: baseDelay, maxDelay: maxDelay);
    debugPrint(
      'zuno/retry: sender key delivery failed (attempt $n), retrying in '
      '$delay: $error',
    );
    delivery.retry = Timer(
      delay,
      () => unawaited(_attempt({id: delivery}, content, n + 1)),
    );
  }

  DeviceKeys? _known(VoipParticipantId id) =>
      _client.userDeviceKeys[id.userId]?.deviceKeys[id.deviceId];

  Future<Map<VoipParticipantId, DeviceKeys>> _devicesOf(
    Iterable<VoipParticipantId> ids,
  ) async {
    final unknownUsers = {
      for (final id in ids)
        if (_known(id) == null &&
            _client.userDeviceKeys[id.userId]?.outdated != false)
          id.userId,
    };
    if (unknownUsers.isNotEmpty) {
      await _client.updateUserDeviceKeys(additionalUsers: unknownUsers);
    }
    return {for (final id in ids) id: ?_known(id)};
  }
}

class _Delivery {
  _Delivery(this.mark);

  final SenderKeyMark mark;
  Timer? retry;

  void stop() => retry?.cancel();
}
