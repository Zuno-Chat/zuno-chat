import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

class FakeDatabaseApi implements DatabaseApi {
  @override
  Future<User?> getUser(String userId, Room room) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

class StoredEventsFakeDatabaseApi extends TimelineCapableFakeDatabaseApi {
  List<Event> events = [];

  @override
  Future<Event?> getEventById(String eventId, Room room) async =>
      events.where((e) => e.eventId == eventId).firstOrNull;

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

class UploadingFakeDatabaseApi extends MediaCapableFakeDatabaseApi {
  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
  getCustomCacheObject(String cacheKey) async =>
      (content: const <String, Object?>{}, savedAt: DateTime.now());
}

Client buildTestClient({
  String? userId,
  String? deviceId,
  http.Client? httpClient,
  DatabaseApi? database,
}) {
  final db = database ?? FakeDatabaseApi();
  final client = deviceId == null
      ? Client('test', database: db, httpClient: httpClient)
      : (_TestClient('test', database: db, httpClient: httpClient)
          ..testDeviceId = deviceId);
  if (userId != null) client.setUserId(userId);
  return client;
}

class _TestClient extends Client {
  _TestClient(super.clientName, {required super.database, super.httpClient});

  String? testDeviceId;

  @override
  String? get deviceID => testDeviceId;
}

class ExpiringTokenClient extends Client {
  ExpiringTokenClient({
    this.expiresIn = const Duration(seconds: 30),
    bool refreshStalls = false,
  }) : super(
         'test',
         database: FakeDatabaseApi(),
         onSoftLogout: refreshStalls
             ? (_) => Completer<void>().future
             : (client) async => client.accessToken = 'fresh',
       );

  final Duration expiresIn;

  @override
  DateTime? get accessTokenExpiresAt => DateTime.now().add(expiresIn);

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

Event buildTestEvent(
  Room room, {
  required String eventId,
  required String senderId,
  String type = EventTypes.Message,
  Map<String, Object?> content = const {},
  DateTime? originServerTs,
  String? stateKey,
  EventStatus? status,
}) {
  final event = Event(
    eventId: eventId,
    type: type,
    senderId: senderId,
    originServerTs: originServerTs ?? DateTime.now(),
    content: content,
    room: room,
    stateKey: stateKey,
  );
  if (status != null) event.status = status;
  return event;
}
