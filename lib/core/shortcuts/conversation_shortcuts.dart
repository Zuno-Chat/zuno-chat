import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../errors/caught_errors.dart';
import '../matrix/matrix_client_provider.dart';
import '../platform/platform_capabilities.dart';

const _channel = MethodChannel('zuno/conversations');

final conversationShortcutsProvider = Provider<void>((ref) {
  if (!ref.watch(platformCapabilitiesProvider).notificationAvatars) return;
  final client = ref.watch(matrixClientProvider);
  var reconciled = false;
  final sub = client.onSync.stream.listen((update) {
    if (reconciled && (update.rooms?.leave?.isEmpty ?? true)) return;
    reconciled = true;
    unawaited(_retainConversationShortcuts(_roomsYouAreIn(client)));
  });
  ref.onDispose(sub.cancel);
});

List<String> _roomsYouAreIn(Client client) => [
  for (final room in client.rooms)
    if (room.membership == Membership.join ||
        room.membership == Membership.invite)
      room.id,
];

Future<void> _retainConversationShortcuts(List<String> roomIds) async {
  try {
    await _channel.invokeMethod<void>('retainConversationShortcuts', {
      'roomIds': roomIds,
    });
  } on MissingPluginException catch (e, s) {
    reportCaught('remove the shortcuts of rooms left', e, s);
  } on PlatformException catch (e, s) {
    reportCaught('remove the shortcuts of rooms left', e, s);
  }
}
