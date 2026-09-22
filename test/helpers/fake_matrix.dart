import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

class FakeDatabaseApi implements DatabaseApi {
  @override
  Future<User?> getUser(String userId, Room room) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
