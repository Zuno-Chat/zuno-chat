import 'dart:async';

import 'package:flutter_riverpod/misc.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/live_location_capture.dart';
import 'package:zuno/core/location/live_location_policy.dart';
import 'package:zuno/core/location/live_location_protocol.dart';
import 'package:zuno/core/location/live_location_sharing.dart';
import 'package:zuno/core/location/live_location_viewing.dart';
import 'package:zuno/core/location/map_tiles_provider.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';

import 'fake_matrix.dart';

class FakeLiveLocationCapture implements LiveLocationCapture {
  final _events = StreamController<LiveCaptureEvent>.broadcast();
  final _stops = StreamController<void>.broadcast();
  final calls = <String>[];
  final released = <int>[];
  LiveLocationMode? mode;
  LiveLocationNotice? notice;
  bool running = false;
  Object? startError;

  @override
  Stream<LiveCaptureEvent> get events => _events.stream;

  @override
  Stream<void> get stopRequests => _stops.stream;

  @override
  Future<void> start(LiveLocationMode mode, LiveLocationNotice notice) async {
    calls.add('start');
    if (startError case final error?) throw error;
    running = true;
    this.mode = mode;
    this.notice = notice;
  }

  @override
  Future<void> setMode(LiveLocationMode mode) async {
    calls.add('setMode');
    this.mode = mode;
  }

  @override
  Future<void> updateNotice(LiveLocationNotice notice) async {
    this.notice = notice;
  }

  @override
  Future<void> releaseWakeLock(int seq) async => released.add(seq);

  @override
  Future<void> stop() async {
    calls.add('stop');
    running = false;
    mode = null;
  }

  void fix(LivePosition position, int seq) =>
      _events.add(LiveCaptureFix(LiveFix(position: position, seq: seq)));

  void lose(LiveCaptureFailure reason) => _events.add(LiveCaptureLost(reason));

  void requestStop() => _stops.add(null);
}

typedef LiveStateWrite = ({
  String roomId,
  String stateKey,
  Map<String, Object?> content,
});
typedef LiveToDeviceSend = ({
  List<String> devices,
  String type,
  Map<String, dynamic> content,
});

class LiveLocationTestClient extends Client {
  LiveLocationTestClient()
    : super('test', database: SendCapableFakeDatabaseApi()) {
    setUserId('@me:x');
  }

  final stateWrites = <LiveStateWrite>[];
  final journal = <String>[];
  final ignored = <String>[];
  Object? sendError;
  final toDevice = <LiveToDeviceSend>[];
  final serverStateReads = <String>[];
  Map<String, Map<String, Object?>> serverState = {};
  Object? stateWriteError;
  Completer<void>? holdStateWrites;
  Completer<void>? holdSends;
  var _events = 0;

  @override
  String? get deviceID => 'MINE';

  @override
  bool get encryptionEnabled => true;

  @override
  List<String> get ignoredUsers => List.of(ignored);

  @override
  Future<String> setRoomStateWithKey(
    String roomId,
    String eventType,
    String stateKey,
    Map<String, Object?> body,
  ) async {
    if (holdStateWrites case final hold?) await hold.future;
    if (stateWriteError case final error?) throw error;
    stateWrites.add((roomId: roomId, stateKey: stateKey, content: body));
    journal.add(body.isEmpty ? 'share cleared' : 'share published');
    serverState[roomId] = body;
    return '\$state${_events++}';
  }

  @override
  Future<void> logout() async => journal.add('logged out');

  @override
  Future<Map<String, Object?>> getRoomStateWithKey(
    String roomId,
    String eventType,
    String stateKey, {
    Format? format,
  }) async {
    serverStateReads.add(roomId);
    final content = eventType == liveLocationStateType
        ? serverState[roomId]
        : null;
    if (content == null) {
      throw MatrixException.fromJson({
        'errcode': 'M_NOT_FOUND',
        'error': 'Event not found.',
      });
    }
    return content;
  }

  @override
  Future<void> sendToDeviceEncrypted(
    List<DeviceKeys> deviceKeys,
    String eventType,
    Map<String, dynamic> message, {
    String? messageId,
    bool onlyVerified = false,
  }) async {
    if (holdSends case final hold?) await hold.future;
    if (sendError case final error?) throw error;
    toDevice.add((
      devices: [for (final d in deviceKeys) '${d.userId}/${d.deviceId}'],
      type: eventType,
      content: message,
    ));
  }
}

class LiveLocationTestRoom extends Room {
  LiveLocationTestRoom({required super.id, required super.client});

  final sent = <Map<String, dynamic>>[];
  bool allowState = true;
  bool direct = false;
  bool sendFails = false;
  String title = 'Family';

  @override
  bool canChangeStateEvent(String action) => allowState;

  @override
  bool get encrypted => true;

  @override
  bool get canSendDefaultMessages => true;

  @override
  bool get isDirectChat => direct;

  @override
  String getLocalizedDisplayname([
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  ]) => title;

  @override
  Future<String?> sendEvent(
    Map<String, dynamic> content, {
    String type = EventTypes.Message,
    String? txid,
    Event? inReplyTo,
    String? editEventId,
    String? threadRootEventId,
    String? threadLastEventId,
    bool displayPendingEvent = true,
  }) async {
    sent.add(content);
    return sendFails ? null : '\$start-$id';
  }
}

class LiveLocationHarness {
  LiveLocationHarness() {
    room = LiveLocationTestRoom(id: '!family:x', client: client);
    client.rooms.add(room);
    member('@me:x', 'Me');
  }

  final client = LiveLocationTestClient();
  final capture = FakeLiveLocationCapture();
  late final LiveLocationTestRoom room;
  LiveLocationSharing? _sharing;
  LiveLocationViewing? _viewing;

  LiveLocationSharing get sharing => _sharing ??= LiveLocationSharing(
    client: client,
    capture: capture,
    isOffline: () => false,
    recipients: (_) async => const [],
  );

  LiveLocationViewing get viewing => _viewing ??= _startViewing();

  LiveLocationViewing _startViewing() =>
      LiveLocationViewing(client: client, isOffline: () => false);

  List<Override> get overrides => [
    matrixClientProvider.overrideWithValue(client),
    liveLocationSharingProvider.overrideWith((ref) {
      ref.onDispose(sharing.dispose);
      return sharing;
    }),
    liveLocationViewingProvider.overrideWith((ref) {
      ref.onDispose(viewing.dispose);
      return viewing;
    }),
    mapTilesProvider.overrideWith((ref) async => null),
  ];

  Future<void> startSharing({
    GeoUri geo = const GeoUri(latitude: 52.5, longitude: 13.4),
  }) => sharing.start(
    room,
    LiveLocationDuration.hour,
    LivePosition(geo: geo, at: DateTime.now()),
  );

  void member(String userId, String name) => room.setState(
    Event(
      type: EventTypes.RoomMember,
      stateKey: userId,
      senderId: userId,
      eventId: '\$member-$userId',
      originServerTs: DateTime.now(),
      content: {'membership': 'join', 'displayname': name},
      room: room,
    ),
  );

  void shareFrom(
    String userId, {
    String deviceId = 'PHONE',
    String shareId = 'share1',
    Duration lasting = const Duration(hours: 1),
  }) {
    final now = DateTime.now();
    room.setState(
      Event(
        type: liveLocationStateType,
        stateKey: userId,
        senderId: userId,
        eventId: '\$state-$userId-$shareId',
        originServerTs: now,
        content: LiveShareState(
          shareId: shareId,
          deviceId: deviceId,
          endsAt: now.add(lasting),
        ).toContent(),
        room: room,
      ),
    );
  }

  void positionFrom(
    String userId, {
    required String deviceId,
    String shareId = 'share1',
    GeoUri geo = const GeoUri(
      latitude: 52.5,
      longitude: 13.4,
      uncertaintyMeters: 20,
    ),
    DateTime? at,
  }) {
    _viewing ??= _startViewing();
    client.onToDeviceEvent.add(
      ToDeviceEvent(
        sender: userId,
        type: liveLocationPositionType,
        content: livePositionContent(
          roomId: room.id,
          shareId: shareId,
          position: LivePosition(geo: geo, at: at ?? DateTime.now()),
        ),
        encryptedContent: {'sender_key': 'curve-$deviceId'},
      ),
    );
  }

  Event startMessage(String senderId, {String shareId = 'share1'}) => Event(
    type: EventTypes.Message,
    senderId: senderId,
    eventId: '\$start-$senderId',
    originServerTs: DateTime.now(),
    content: liveLocationStartContent(
      shareId: shareId,
      endsAt: DateTime.now().add(const Duration(hours: 1)),
      duration: LiveLocationDuration.hour,
    ),
    room: room,
  );

  void dispose() {
    _sharing?.dispose();
    _viewing?.dispose();
  }
}
