import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/services.dart';

import '../errors/caught_errors.dart';
import '../platform/platform_capabilities.dart';

enum NativeNotificationActionKind { reply, markRead }

@immutable
class NativeNotificationAction {
  const NativeNotificationAction({
    required this.id,
    required this.kind,
    this.roomId,
    this.roomToken,
    this.eventId,
    this.eventSeconds,
    this.replyText,
  });

  final String id;
  final NativeNotificationActionKind kind;
  final String? roomId;
  final String? roomToken;
  final String? eventId;
  final int? eventSeconds;
  final String? replyText;

  @override
  bool operator ==(Object other) =>
      other is NativeNotificationAction &&
      other.id == id &&
      other.kind == kind &&
      other.roomId == roomId &&
      other.roomToken == roomToken &&
      other.eventId == eventId &&
      other.eventSeconds == eventSeconds &&
      other.replyText == replyText;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    roomId,
    roomToken,
    eventId,
    eventSeconds,
    replyText,
  );

  @override
  String toString() =>
      'NativeNotificationAction($id, ${kind.name}, room: $roomId, '
      'token: $roomToken, event: $eventId, at: $eventSeconds)';
}

typedef NativeActionBatch = ({
  List<NativeNotificationAction> actions,
  List<String> unreadable,
});

const NativeActionBatch _noActions = (
  actions: <NativeNotificationAction>[],
  unreadable: <String>[],
);

class NativeNotificationActionsChannel {
  NativeNotificationActionsChannel({
    PlatformCapabilities? capabilities,
    MethodChannel channel = const MethodChannel('zuno/notification_actions'),
  }) : _injectedCapabilities = capabilities,
       _methods = channel;

  final PlatformCapabilities? _injectedCapabilities;
  final MethodChannel _methods;

  bool get enabled =>
      (_injectedCapabilities ?? ambientCapabilities).nativeNotificationActions;

  Future<NativeActionBatch> take() async {
    if (!enabled) return _noActions;
    final List<Object?>? raw;
    try {
      raw = await _methods.invokeListMethod<Object?>('takeActions');
    } on MissingPluginException {
      return _noActions;
    } on PlatformException catch (e, s) {
      reportCaught('native actions take', e, s);
      return _noActions;
    }
    final actions = <NativeNotificationAction>[];
    final unreadable = <String>[];
    for (final entry in raw ?? const <Object?>[]) {
      final action = _actionFrom(entry);
      if (action != null) {
        actions.add(action);
        continue;
      }
      final id = entry is Map ? entry['id'] : null;
      if (id is String && id.isNotEmpty) unreadable.add(id);
    }
    return (actions: actions, unreadable: unreadable);
  }

  Future<void> finish(String id, {required bool ok}) async {
    if (!enabled) return;
    try {
      await _methods.invokeMethod<void>('finish', {'id': id, 'ok': ok});
    } on MissingPluginException {
      return;
    } on PlatformException catch (e, s) {
      reportCaught('native action finish', e, s);
    }
  }

  void listen(void Function() onAvailable) {
    if (!enabled) return;
    _methods.setMethodCallHandler((call) async {
      if (call.method == 'actionsAvailable') onAvailable();
      return null;
    });
  }
}

NativeNotificationAction? _actionFrom(Object? entry) {
  if (entry is! Map) return null;
  final id = entry['id'];
  final kind = switch (entry['kind']) {
    'reply' => NativeNotificationActionKind.reply,
    'markRead' => NativeNotificationActionKind.markRead,
    _ => null,
  };
  if (id is! String || id.isEmpty || kind == null) return null;
  final roomId = _text(entry['roomId']);
  final roomToken = _text(entry['roomToken']);
  if (roomId == null && roomToken == null) return null;
  final seconds = entry['eventSeconds'];
  final replyText = entry['replyText'];
  return NativeNotificationAction(
    id: id,
    kind: kind,
    roomId: roomId,
    roomToken: roomToken,
    eventId: _text(entry['eventId']),
    eventSeconds: seconds is int && seconds > 0 ? seconds : null,
    replyText: replyText is String ? replyText : null,
  );
}

String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;
