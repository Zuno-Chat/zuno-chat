import 'dart:convert';

import 'package:http/http.dart' show Request;
import 'package:matrix/matrix.dart';

import 'client_lease.dart';
import 'send_keep_awake.dart';
import 'sync_coordinator.dart';

const lateKeySyncWait = Duration(seconds: 6);

Future<void>? syncForLateKey(Client client) {
  final sync = client is ZunoClient
      ? client.syncForPush(timeout: lateKeySyncWait)
      : client.oneShotSync(timeout: lateKeySyncWait);
  return sync?.then<void>((_) {}, onError: (_) {});
}

class ZunoClient extends Client {
  ZunoClient(
    super.clientName, {
    required super.database,
    super.httpClient,
    super.verificationMethods,
    super.roomPreviewLastEvents,
    super.nativeImplementations,
    super.onSoftLogout,
    super.shareKeysWith,
    this.appClient = true,
    this.lease,
    this.keepAwake,
  });

  final bool appClient;
  final ClientLease? lease;
  final SendKeepAwake? keepAwake;
  SyncCoordinator? syncCoordinator;

  bool _restoringSession = false;

  // FIXME: matrix SDK adds a sync loop per mid-request abortSync() (upstream).
  @override
  set backgroundSync(bool enabled) =>
      super.backgroundSync = enabled && syncCoordinator == null;

  Future<void> restoreSession({bool waitForStoreLoad = true}) async {
    _restoringSession = true;
    try {
      await init(
        waitForFirstSync: false,
        waitUntilLoadCompletedLoaded: waitForStoreLoad,
      );
    } finally {
      _restoringSession = false;
    }
  }

  @override
  Future<void> clear({
    SessionClearReason reason = SessionClearReason.unspecified,
  }) async {
    if (!appClient) {
      Logs().w('A background client kept the shared store ($reason)');
      return;
    }
    if (_restoringSession && reason == SessionClearReason.initFailed) return;
    syncCoordinator?.cancelWaitingRequest();
    await super.clear(reason: reason);
  }

  @override
  Future<void> clearCache() =>
      syncCoordinator?.whileIdle(super.clearCache) ?? super.clearCache();

  @override
  Future<void> sendToDeviceEncrypted(
    List<DeviceKeys> deviceKeys,
    String eventType,
    Map<String, dynamic> message, {
    String? messageId,
    bool onlyVerified = false,
  }) {
    Future<void> send() => super.sendToDeviceEncrypted(
      deviceKeys,
      eventType,
      message,
      messageId: messageId,
      onlyVerified: onlyVerified,
    );
    return keepAwake?.hold(send) ?? send();
  }

  @override
  Future<String> sendMessage(
    String roomId,
    String eventType,
    String txnId,
    Map<String, Object?> body,
  ) {
    Future<String> send() => super.sendMessage(roomId, eventType, txnId, body);
    return keepAwake?.hold(send) ?? send();
  }

  @override
  Future<Event?> getEventByPushNotification(
    PushNotification notification, {
    bool storeInDatabase = true,
    Duration timeoutForServerRequests = const Duration(seconds: 8),
    bool returnNullIfSeen = true,
  }) async {
    await ensureNotSoftLoggedOut();
    final eventId = notification.eventId;
    final roomId = notification.roomId;
    if (eventId == null || roomId == null) return null;
    var room =
        getRoomById(roomId) ?? await database.getSingleRoom(this, roomId);
    if (room == null) {
      await syncForPush()
          ?.timeout(timeoutForServerRequests)
          .then<void>((_) {}, onError: (_) {});
      room = getRoomById(roomId) ?? Room(id: roomId, client: this);
    }
    MatrixEvent? matrixEvent = await database.getEventById(eventId, room);
    try {
      matrixEvent ??= await getOneRoomEvent(
        roomId,
        eventId,
      ).timeout(timeoutForServerRequests);
    } on MatrixException catch (_) {
      await ensureNotSoftLoggedOut();
      matrixEvent ??= (await getNotifications()).notifications
          .where((n) => n.roomId == roomId && n.event.eventId == eventId)
          .firstOrNull
          ?.event;
    }
    if (matrixEvent == null) {
      throw Exception('Unable to find event for this push notification!');
    }
    if (returnNullIfSeen && await _readBefore(room, matrixEvent)) return null;
    try {
      await room
          .requestUser(matrixEvent.senderId)
          .timeout(timeoutForServerRequests);
    } catch (e, s) {
      Logs().w('Unable to request user for push helper', e, s);
    }
    var event = Event.fromMatrixEvent(
      matrixEvent,
      room,
      status: EventStatus.sent,
    );
    final encryption = this.encryption;
    if (event.type == EventTypes.Encrypted && encryption != null) {
      event = await encryption.decryptRoomEvent(event);
    }
    if (storeInDatabase) {
      await database.transaction(
        () => database.storeEventUpdate(
          roomId,
          event,
          EventUpdateType.timeline,
          this,
        ),
      );
    }
    return event;
  }

  @override
  Future<SyncUpdate> sync({
    String? filter,
    String? since,
    bool? fullState,
    PresenceType? setPresence,
    int? timeout,
    bool? useStateAfter,
  }) async {
    final request = Request(
      'GET',
      baseUri!.resolveUri(
        Uri(
          path: '_matrix/client/v3/sync',
          queryParameters: {
            'filter': ?filter,
            'since': ?since,
            if (fullState != null) 'full_state': '$fullState',
            if (setPresence != null) 'set_presence': setPresence.name,
            if (timeout != null) 'timeout': '$timeout',
            'use_state_after': 'true',
          },
        ),
      ),
    );
    request.headers['authorization'] = 'Bearer ${bearerToken!}';
    final response = await httpClient.send(request);
    final body = await response.stream.toBytes();
    if (response.statusCode != 200) unexpectedResponse(response, body);
    final json = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
    if (json['rooms'] case final Map<String, Object?> rooms) {
      for (final section in [rooms['join'], rooms['leave']]) {
        if (section is! Map<String, Object?>) continue;
        for (final room in section.values.whereType<Map<String, Object?>>()) {
          if (room.remove('state_after') case final after?) {
            room['state'] = after;
          }
        }
      }
    }
    return SyncUpdate.fromJson(json);
  }

  Future<void>? syncForPush({Duration? timeout}) =>
      syncCoordinator != null && !syncPending
      ? null
      : oneShotSync(timeout: timeout);

  Future<bool> _readBefore(Room room, MatrixEvent event) async {
    if (room.fullyRead == event.eventId) return true;
    final marker = await database.getEventById(room.fullyRead, room);
    return marker != null &&
        marker.originServerTs.isAfter(event.originServerTs);
  }

  @override
  Future<void> dispose({bool closeDatabase = true}) async {
    syncCoordinator?.dispose();
    try {
      await super.dispose(closeDatabase: closeDatabase);
    } finally {
      await lease?.release();
    }
  }
}
