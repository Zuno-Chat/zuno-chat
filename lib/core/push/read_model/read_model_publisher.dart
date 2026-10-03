import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../matrix/matrix_client_provider.dart';
import '../../matrix/room_title.dart';
import '../../platform/platform_capabilities.dart';
import '../../settings/app_preferences_provider.dart';
import '../voip/voip_registration.dart';
import 'nse_channel.dart';

const readModelSessionKey = 'push.readmodel.session';

typedef MetaInputs = ({
  String user,
  String device,
  int? serverOffsetMs,
  bool ringtone,
  bool voipCurrent,
});

typedef ReadModelMetaExtras = Future<Map<String, Object?>> Function();
typedef ReadModelRoomExtras = Future<Map<String, Object?>> Function(Room room);

Map<String, Object?> _withExtras(
  Map<String, Object?> fields,
  Map<String, Object?> extras,
) => {
  ...fields,
  for (final MapEntry(:key, :value) in extras.entries)
    if (!fields.containsKey(key)) key: value,
};

String metaJson(
  MetaInputs meta, {
  required int heartbeatMs,
  Map<String, Object?> extras = const {},
}) => jsonEncode(
  _withExtras({
    'v': 1,
    'user': meta.user,
    'device': meta.device,
    'server_offset_ms': meta.serverOffsetMs,
    'ringtone': meta.ringtone,
    'voip_current': meta.voipCurrent,
    'heartbeat_ms': heartbeatMs,
  }, extras),
);

String roomJson(
  Room room, {
  bool titles = true,
  Map<String, Object?> extras = const {},
}) {
  final partnerId = room.isDirectChat ? room.directChatMatrixID : null;
  return jsonEncode(
    _withExtras({
      'v': 1,
      'room': room.id,
      'title': titles ? roomTitle(room) : '',
      'dm': room.isDirectChat,
      'partner': !titles || partnerId == null
          ? ''
          : room.unsafeGetUserFromMemoryOrFallback(partnerId).calcDisplayname(),
    }, extras),
  );
}

Iterable<String> changedRoomIds(SyncUpdate update) => {
  ...?update.rooms?.join?.keys,
  ...?update.rooms?.invite?.keys,
  ...?update.rooms?.leave?.keys,
};

class ReadModelPublisher {
  ReadModelPublisher({
    NseChannel nse = const NseChannel(),
    DateTime Function()? now,
    Duration debounce = const Duration(seconds: 1),
  }) : _channel = nse,
       _now = now ?? DateTime.now,
       _debounceDelay = debounce;

  final NseChannel _channel;
  final DateTime Function() _now;
  final Duration _debounceDelay;
  final _published = <String, String>{};
  final _pending = <String>{};
  Timer? _debounce;
  Client? _client;
  MetaInputs? _meta;
  ReadModelMetaExtras? metaExtras;
  ReadModelRoomExtras? roomExtras;
  bool titles = true;
  bool holdUntilExtras = false;

  bool get _held => holdUntilExtras && metaExtras == null;

  Future<void> start(Client client, MetaInputs meta) async {
    _client = client;
    final prefs = await SharedPreferences.getInstance();
    final session = '${meta.user}|${meta.device}';
    if (prefs.getString(readModelSessionKey) != session) {
      await _channel.wipe();
      _published.clear();
      await prefs.setString(readModelSessionKey, session);
    }
    if (_client == null) return;
    await writeMeta(meta);
    for (final room in [...client.rooms]) {
      await _publish(room);
    }
  }

  Future<void> writeMeta(MetaInputs meta) async {
    _meta = meta;
    if (_held) return;
    final extras = await metaExtras?.call() ?? const <String, Object?>{};
    if (_held || _client == null) return;
    await _channel.writeMeta(
      metaJson(
        meta,
        heartbeatMs: _now().millisecondsSinceEpoch,
        extras: extras,
      ),
    );
  }

  Future<void> refreshMeta() async {
    final meta = _meta;
    if (_client != null && meta != null) await writeMeta(meta);
  }

  Future<void> publishAll({bool force = false}) async {
    final client = _client;
    if (client == null) return;
    if (force) _published.clear();
    for (final room in [...client.rooms]) {
      await _publish(room);
    }
  }

  void roomsChanged(Iterable<String> roomIds) {
    if (_client == null) return;
    _pending.addAll(roomIds);
    if (_pending.isEmpty) return;
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () => unawaited(flush()));
  }

  Future<void> flush() async {
    _debounce?.cancel();
    _debounce = null;
    final client = _client;
    if (client == null) return;
    final roomIds = [..._pending];
    _pending.clear();
    for (final roomId in roomIds) {
      final room = client.getRoomById(roomId);
      if (room == null || !_publishes(room)) {
        _published.remove(roomId);
        await _channel.deleteRoom(roomId);
      } else {
        await _publish(room);
      }
    }
  }

  void stop() {
    _debounce?.cancel();
    _debounce = null;
    _pending.clear();
    _client = null;
    _meta = null;
  }

  bool _publishes(Room room) =>
      room.membership == Membership.join && !room.isSpace;

  Future<void> _publish(Room room) async {
    if (!_publishes(room) || _held) return;
    final Map<String, Object?> extras;
    try {
      extras = await roomExtras?.call(room) ?? const <String, Object?>{};
    } catch (e) {
      debugPrint('zuno/nse: a room file was skipped (${e.runtimeType})');
      return;
    }
    if (_held || _client == null) return;
    final json = roomJson(room, titles: titles, extras: extras);
    if (_published[room.id] == json) return;
    if (await _channel.writeRoom(room.id, json)) _published[room.id] = json;
  }
}

final readModelPublisherProvider = Provider<ReadModelPublisher?>((ref) {
  final capabilities = ref.watch(platformCapabilitiesProvider);
  if (!capabilities.voipRing) return null;
  final client = ref.watch(matrixClientProvider);
  final registration = ref.watch(voipRegistrationProvider);
  final publisher = ReadModelPublisher()
    ..holdUntilExtras = capabilities.nseNotifications;

  MetaInputs? inputs() {
    final user = client.userID;
    final device = client.deviceID;
    if (user == null || device == null || !client.isLogged()) return null;
    return (
      user: user,
      device: device,
      serverOffsetMs: registration.serverOffsetMs.value,
      ringtone: ref.read(ringtoneEnabledProvider),
      voipCurrent: registration.current.value,
    );
  }

  void refreshMeta() {
    final meta = inputs();
    if (meta != null) unawaited(publisher.writeMeta(meta));
  }

  ref.listen(isLoggedInProvider, (_, loggedIn) {
    final meta = inputs();
    if (loggedIn.value == true && meta != null) {
      unawaited(publisher.start(client, meta));
    } else if (loggedIn.value == false) {
      publisher.stop();
    }
  }, fireImmediately: true);
  ref.listen(ringtoneEnabledProvider, (_, _) => refreshMeta());
  registration.current.addListener(refreshMeta);
  registration.serverOffsetMs.addListener(refreshMeta);
  final sync = client.onSync.stream.listen(
    (update) => publisher.roomsChanged(changedRoomIds(update)),
  );
  final lifecycle = AppLifecycleListener(
    onPause: () => unawaited(publisher.flush()),
    onResume: refreshMeta,
  );
  ref.onDispose(() {
    registration.current.removeListener(refreshMeta);
    registration.serverOffsetMs.removeListener(refreshMeta);
    unawaited(sync.cancel());
    lifecycle.dispose();
    publisher.stop();
  });
  return publisher;
});
