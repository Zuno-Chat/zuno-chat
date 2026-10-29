import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/ui/notice.dart';
import '../../share/presentation/forward_picker_page.dart';
import '../data/forward_uploads.dart';
import '../data/room_sender.dart';

Future<void> forwardMedia(
  BuildContext context,
  WidgetRef ref,
  List<Event> items,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final source = items.first.room;
  final rooms = await pickForwardTargets(
    context,
    client: source.client,
    fromEncrypted: source.encrypted,
  );
  if (rooms == null || !context.mounted) return;
  final uploads = ForwardUploads();
  final failures = await Future.wait([
    for (final room in rooms)
      ref.read(roomSenderProvider(room)).forward(items, uploads: uploads),
  ]);
  final failed = [
    for (final (i, room) in rooms.indexed)
      if (failures[i] case final error?) (room: room, error: error),
  ];
  switch (failed) {
    case []:
      messenger.say(l10n.chatForwardSent(rooms.length));
    case [(:final room, :final error)]:
      messenger.sayFailed(
        l10n,
        error,
        failed: l10n.chatForwardFailedOne(roomTitle(room, l10n)),
      );
    case [final first, ...]:
      messenger.sayFailed(
        l10n,
        first.error,
        failed: l10n.chatForwardFailedMany(failed.length),
      );
  }
}
