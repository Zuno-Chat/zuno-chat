import 'dart:async';

import 'package:matrix/matrix.dart';

import '../errors/best_effort.dart';
import 'live_location_protocol.dart';

const _sweepRetryGap = Duration(minutes: 1);

typedef _Refusal = ({String stateEventId, String? powerLevelsEventId});

class LiveShareSweep {
  LiveShareSweep({
    required this._client,
    required this._isActive,
    required this._writeState,
    required this._echoState,
    required this._now,
  });

  final Client _client;
  final bool Function(String roomId) _isActive;
  final Future<String> Function(String roomId, Map<String, Object?> content)
  _writeState;
  final void Function(Room room, String eventId, Map<String, Object?> content)
  _echoState;
  final DateTime Function() _now;
  final _sweptAt = <String, DateTime>{};
  final _refusedClears = <String, _Refusal>{};

  void sweep([SyncUpdate? update]) {
    final userId = _client.userID;
    final deviceId = _client.deviceID;
    if (userId == null || deviceId == null) return;
    final now = _now();
    for (final room in _client.rooms) {
      if (room.membership != Membership.join) continue;
      if (_isActive(room.id)) continue;
      final event = room.states[liveLocationStateType]?[userId];
      if (event is! MatrixEvent || event.senderId != userId) continue;
      final state = parseLiveShareState(
        event.content,
        publishedAt: event.originServerTs,
      );
      if (state == null || !state.isOpenAt(now)) continue;
      final ownedHere = state.deviceId == deviceId;
      if (!ownedHere && !_rejoined(update, room.id, userId)) continue;
      final refusal = _refusedClears[room.id];
      if (refusal != null &&
          refusal.stateEventId == event.eventId &&
          refusal.powerLevelsEventId == _powerLevelsEventId(room)) {
        continue;
      }
      final lastTry = _sweptAt[room.id];
      if (lastTry != null &&
          !now.isBefore(lastTry) &&
          now.difference(lastTry) < _sweepRetryGap) {
        continue;
      }
      _sweptAt[room.id] = now;
      unawaited(
        _clear(
          room,
          userId: userId,
          deviceId: state.deviceId,
          stateEventId: event.eventId,
        ),
      );
    }
  }

  bool _rejoined(SyncUpdate? update, String roomId, String userId) {
    final roomUpdate = update?.rooms?.join?[roomId];
    if (roomUpdate == null) return false;
    return [...?roomUpdate.state, ...?roomUpdate.timeline?.events].any((event) {
      if (event.type != EventTypes.RoomMember || event.stateKey != userId) {
        return false;
      }
      final previous =
          event.prevContent ??
          (event.unsigned?['prev_content'] as Map<String, Object?>?);
      return event.content['membership'] == Membership.join.name &&
          previous?['membership'] != Membership.join.name;
    });
  }

  Future<void> _clear(
    Room room, {
    required String userId,
    required String deviceId,
    required String stateEventId,
  }) async {
    try {
      final content = await _client.getRoomStateWithKey(
        room.id,
        liveLocationStateType,
        userId,
      );
      if (content['device_id'] != deviceId) return;
      if (_isActive(room.id)) return;
      final eventId = await _writeState(room.id, const {});
      if (!_isActive(room.id)) _echoState(room, eventId, const {});
    } on MatrixException catch (error) {
      if (error.error == MatrixError.M_FORBIDDEN) {
        _refusedClears[room.id] = (
          stateEventId: stateEventId,
          powerLevelsEventId: _powerLevelsEventId(room),
        );
      } else if (error.error != MatrixError.M_NOT_FOUND) {
        logCaught('live location leftover', error);
      }
    } catch (error) {
      logCaught('live location leftover', error);
    }
  }
}

String? _powerLevelsEventId(Room room) {
  final powerLevels = room.getState(EventTypes.RoomPowerLevels);
  return powerLevels is MatrixEvent ? powerLevels.eventId : null;
}
