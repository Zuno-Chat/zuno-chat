import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/location/map_tile_cache.dart';
import '../../../core/matrix/auth_error_message.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/notifications/notification_delivery_provider.dart';
import '../../../core/security/new_device_alert_provider.dart';
import '../../../core/ui/circle_icon.dart';
import 'uia_password_prompt.dart';

class DeleteAccountTile extends ConsumerStatefulWidget {
  const DeleteAccountTile({super.key});

  @override
  ConsumerState<DeleteAccountTile> createState() => _DeleteAccountTileState();
}

class _DeleteAccountTileState extends ConsumerState<DeleteAccountTile> {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: const CircleIcon(Icons.delete_forever_outlined, danger: true),
      title: Text('Delete account', style: TextStyle(color: colors.error)),
      onTap: _start,
    );
  }

  Future<void> _start() async {
    final proceed = await _confirmWarning();
    if (proceed != true || !mounted) return;

    final matches = await _confirmTypedId();
    if (matches != true || !mounted) return;

    await _deactivate();
  }

  Future<bool?> _confirmWarning() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'Your account, profile and messages are permanently removed. People '
          'you have messaged keep their copies. Nobody can reach you at this '
          'username again, and nobody can undo this.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmTypedId() {
    final client = ref.read(matrixClientProvider);
    final userId = client.userID ?? '';
    final username = userId.startsWith('@')
        ? userId.substring(1).split(':').first
        : userId;
    final controller = TextEditingController();
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final matches = controller.text == username;
          return AlertDialog(
            title: const Text('Confirm deletion'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Type your username to confirm: $username'),
                const SizedBox(height: 12),
                TextField(
                  autofillHints: null,
                  controller: controller,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: matches
                    ? () => Navigator.of(context).pop(true)
                    : null,
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Delete account'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleUia(UiaRequest uia) async {
    if (uia.state != UiaRequestState.waitForUser) return;
    final client = ref.read(matrixClientProvider);
    final password = await askPasswordForUia(
      context,
      title: 'Confirm your password to delete your account',
    );
    if (!mounted) return;
    if (password == null || password.isEmpty) {
      uia.cancel();
      return;
    }
    await uia.completeStage(
      AuthenticationPassword(
        session: uia.session,
        password: password,
        identifier: AuthenticationUserIdentifier(user: client.userID!),
      ),
    );
  }

  Future<void> _deactivate() async {
    final client = ref.read(matrixClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    final userId = client.userID;
    final uiaSub = client.onUiaRequest.stream.listen(_handleUia);
    try {
      await client.uiaRequestBackground<void>(
        (auth) => client.deactivateAccount(auth: auth, erase: true),
      );
    } catch (e) {
      if (e.toString().contains('canceled')) return;
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(deactivateAccountErrorMessage(e))),
      );
      return;
    } finally {
      await uiaSub.cancel();
    }

    await runBestEffort(
      () => stopAllNotificationDelivery(client),
      label: 'stop notification delivery after account deletion',
    );
    if (userId != null) {
      await runBestEffort(
        () => ref.read(knownDevicesStoreProvider).forget(userId),
        label: 'forget known devices after account deletion',
      );
    }
    await purgeMapTileCache();
    await client.clear(reason: SessionClearReason.logout);
  }
}
