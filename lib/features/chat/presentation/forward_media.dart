import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/room_invite.dart';
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
  final sent = await Future.wait([
    for (final room in rooms)
      ref.read(roomSenderProvider(room)).forward(items, uploads: uploads),
  ]);
  final failed = [
    for (final (i, room) in rooms.indexed)
      if (!sent[i]) room,
  ];
  messenger.showSnackBar(
    SnackBar(
      content: Text(switch (failed) {
        [] => l10n.chatForwardSent(rooms.length),
        [final room] => l10n.chatForwardFailedOne(
          roomInviteDisplay(room, l10n).title,
        ),
        _ => l10n.chatForwardFailedMany(failed.length),
      }),
    ),
  );
}
