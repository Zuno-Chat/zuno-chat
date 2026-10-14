import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/security/user_trust.dart';

class SenderDeviceTile extends ConsumerWidget {
  final Event event;

  const SenderDeviceTile({required this.event, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = event.room.client;
    final senderId = event.senderId;
    if (senderId == client.userID) return const SizedBox.shrink();

    final trust = ref.watch(userTrustProvider(senderId));
    if (trust != UserTrustState.confirmedWithPendingDevice) {
      return const SizedBox.shrink();
    }

    final senderKey = event.originalSource?.content.tryGet<String>(
      'sender_key',
    );
    if (senderKey == null) return const SizedBox.shrink();
    final device = client.getUserDeviceKeysByCurve25519Key(senderKey);
    if (device == null || device.userId != senderId || device.signed) {
      return const SizedBox.shrink();
    }

    return ListTile(
      dense: true,
      leading: const Icon(Icons.smartphone_outlined),
      title: Text(
        context.l10n.chatSenderDeviceUnapproved(withoutServer(senderId)),
      ),
      subtitle: Text(context.l10n.chatSenderDeviceHint),
    );
  }
}
