import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/optimistic_room_state.dart';

class FakeDatabaseApi implements DatabaseApi {
  @override
  Future<User?> getUser(String userId, Room room) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

mixin StoredEventsDatabase on FakeDatabaseApi {
  List<Event> events = [];

  @override
  Future<Event?> getEventById(String eventId, Room room) async =>
      events.where((e) => e.eventId == eventId).firstOrNull;
}

class StoredMembersFakeDatabaseApi extends FakeDatabaseApi
    with StoredEventsDatabase {
  final Map<String, String> displayNames = {};
  final List<String> lookups = [];
  Future<void>? heldLookups;

  @override
  Future<User?> getUser(String userId, Room room) async {
    lookups.add(userId);
    await heldLookups;
    final name = displayNames[userId];
    if (name == null) return null;
    return User(userId, displayName: name, membership: 'join', room: room);
  }
}

class SendCapableFakeDatabaseApi extends FakeDatabaseApi
    with SendCapableDatabase {}

mixin SendCapableDatabase on FakeDatabaseApi {
  @override
  Future<void> transaction(Future<void> Function() action) => action();

  @override
  Future<void> storeEventUpdate(
    String roomId,
    StrippedStateEvent event,
    EventUpdateType type,
    Client client,
  ) async {}

  @override
  Future<void> storeRoomUpdate(
    String roomId,
    SyncRoomUpdate roomUpdate,
    Event? lastEvent,
    Client client,
  ) async {}
}

class TimelineCapableFakeDatabaseApi extends FakeDatabaseApi {
  @override
  Future<void> transaction(Future<void> Function() action) => action();

  @override
  Future<List<User>> getUsers(Room room) async => [];

  @override
  Future<List<Event>> getEventList(
    Room room, {
    int start = 0,
    bool onlySending = false,
    int? limit,
  }) async => [];
}

class StoredEventsFakeDatabaseApi extends TimelineCapableFakeDatabaseApi
    with StoredEventsDatabase {
  @override
  Future<List<Event>> getEventList(
    Room room, {
    int start = 0,
    bool onlySending = false,
    int? limit,
  }) async => onlySending || start > 0 ? [] : events;
}

class ForgettingFakeDatabaseApi extends TimelineCapableFakeDatabaseApi {
  @override
  Future<void> forgetRoom(String roomId) async {}
}

class MediaCapableFakeDatabaseApi extends FakeDatabaseApi
    with MediaCapableDatabase {}

mixin MediaCapableDatabase on FakeDatabaseApi {
  @override
  int get maxFileSize => 0;

  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
  getCustomCacheObject(String cacheKey) async => null;

  @override
  Future<void> cacheCustomObject(
    String cacheKey,
    Map<String, Object?> content,
  ) async {}
}

class SendingFakeDatabaseApi extends StoredEventsFakeDatabaseApi
    with SendCapableDatabase, MediaCapableDatabase {
  final deletedTimelines = <String>[];

  @override
  Future<void> removeEvent(String eventId, String roomId) async {}

  @override
  Future<void> storeFile(Uri mxcUri, Uint8List bytes, int time) async {}

  @override
  Future<bool> deleteFile(Uri mxcUri) async => true;

  @override
  Future<void> deleteTimelineForRoom(String roomId) async =>
      deletedTimelines.add(roomId);

  @override
  Future<void> setRoomPrevBatch(
    String? prevBatch,
    String roomId,
    Client client,
  ) async {}
}

class UploadingFakeDatabaseApi extends MediaCapableFakeDatabaseApi {
  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
  getCustomCacheObject(String cacheKey) async =>
      (content: const <String, Object?>{}, savedAt: clock.now());
}

http.Response? notAMemberAnswer(http.BaseRequest request) =>
    request.method == 'GET' &&
        request.url.pathSegments.contains(EventTypes.RoomMember)
    ? http.Response('{"errcode":"M_NOT_FOUND","error":"Not a member"}', 404)
    : null;

Client buildTestClient({
  String? userId,
  String? deviceId,
  http.Client? httpClient,
  DatabaseApi? database,
  bool encrypting = false,
  Duration sendTimelineEventTimeout = const Duration(minutes: 1),
}) {
  final client = _TestClient(
    'test',
    database: database ?? FakeDatabaseApi(),
    httpClient: httpClient,
    encrypting: encrypting,
    sendTimelineEventTimeout: sendTimelineEventTimeout,
  )..testDeviceId = deviceId;
  if (userId != null) client.setUserId(userId);
  return client;
}

Room namedRoom(
  Client client,
  String id,
  String name, {
  bool encrypted = false,
  Membership membership = Membership.join,
}) {
  final room = Room(id: id, client: client, membership: membership)
    ..partial = false;
  applyOptimisticRoomState(room, EventTypes.RoomName, {'name': name});
  if (encrypted) encryptRoom(room);
  return room;
}

void encryptRoom(Room room) => applyOptimisticRoomState(
  room,
  EventTypes.Encryption,
  {'algorithm': AlgorithmTypes.megolmV1AesSha2},
);

class _TestClient extends Client {
  _TestClient(
    super.clientName, {
    required super.database,
    super.httpClient,
    required this.encrypting,
    required super.sendTimelineEventTimeout,
  });

  final bool encrypting;
  String? testDeviceId;

  @override
  String? get deviceID => testDeviceId ?? super.deviceID;

  @override
  bool get encryptionEnabled => encrypting || super.encryptionEnabled;
}

class ExpiringTokenClient extends Client {
  ExpiringTokenClient({this.expiresIn = const Duration(seconds: 30)})
    : super(
        'test',
        database: FakeDatabaseApi(),
        onSoftLogout: (client) async => client.accessToken = 'fresh',
      );

  final Duration expiresIn;

  @override
  DateTime? get accessTokenExpiresAt => clock.now().add(expiresIn);

  @override
  Future<void> dispose({bool closeDatabase = true}) async {}
}

Room buildTestRoom(
  Client client, {
  String id = '!room:example.org',
  int notificationCount = 0,
}) {
  return Room(id: id, client: client, notificationCount: notificationCount);
}

void setPowerLevels(
  Room room,
  Map<String, Object?> content, {
  String senderId = '@creator:example.org',
}) => room.setState(
  buildTestEvent(
    room,
    eventId: r'$powerlevels',
    senderId: senderId,
    type: EventTypes.RoomPowerLevels,
    stateKey: '',
    content: content,
  ),
);

Event buildTestEvent(
  Room room, {
  required String eventId,
  required String senderId,
  String type = EventTypes.Message,
  Map<String, Object?> content = const {},
  DateTime? originServerTs,
  String? stateKey,
  Map<String, Object?>? prevContent,
  EventStatus? status,
  bool encrypted = false,
  String? senderKey,
}) {
  final sentAt = originServerTs ?? clock.now();
  final event = Event(
    eventId: eventId,
    type: type,
    senderId: senderId,
    originServerTs: sentAt,
    content: content,
    room: room,
    stateKey: stateKey,
    unsigned: prevContent == null ? null : {'prev_content': prevContent},
    originalSource: encrypted
        ? MatrixEvent(
            eventId: eventId,
            type: EventTypes.Encrypted,
            senderId: senderId,
            originServerTs: sentAt,
            content: {
              'algorithm': AlgorithmTypes.megolmV1AesSha2,
              'sender_key': ?senderKey,
            },
          )
        : null,
  );
  if (status != null) event.status = status;
  return event;
}

Event buildTestRedaction(
  Room room,
  String target, {
  String senderId = '@a:example.org',
}) => buildTestEvent(
  room,
  eventId: '\$redacts-${target.substring(1)}',
  senderId: senderId,
  type: EventTypes.Redaction,
  content: {'redacts': target},
);
