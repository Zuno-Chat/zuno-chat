import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

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
        'Sent from a device ${withoutServer(senderId)} has not approved yet',
      ),
      subtitle: const Text(
        'They can approve it from another of their devices. There is nothing '
        'for you to do.',
      ),
    );
  }
}
