import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/active_call_provider.dart';
import '../../../core/errors/best_effort.dart';
import '../../../core/location/live_location_sharing.dart';
import '../../../core/matrix/auth_error_message.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/sign_out.dart';
import '../../../core/notifications/notification_delivery_provider.dart';
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
          'username again, and nobody can undo this. Zuno then erases '
          'everything it stored on this device and closes.',
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
    return showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmDeletionDialog(username: username),
    );
  }

  Future<void> _handleUia(UiaRequest uia) => answerUiaWithPassword(
    context,
    uia,
    userId: ref.read(matrixClientProvider).userID!,
    title: 'Confirm your password to delete your account',
    message: _windDownNotice(),
  );

  String? _windDownNotice() {
    final inCall = ref.read(activeCallProvider) != null;
    final sharing = ref.read(liveLocationSharingProvider).shares.value;
    return switch ((inCall, sharing.isNotEmpty)) {
      (true, true) =>
        'Confirming ends your call and stops sharing your location, even if '
            'the password is wrong.',
      (true, false) =>
        'Confirming ends your call, even if the password is wrong.',
      (false, true) =>
        'Confirming stops sharing your location, even if the password is '
            'wrong.',
      (false, false) => null,
    };
  }

  Future<void> _deactivate() async {
    final client = ref.read(matrixClientProvider);
    final windDown = ref.read(signOutWindDownProvider);
    final messenger = ScaffoldMessenger.of(context);
    final uiaSub = client.onUiaRequest.stream.listen(_handleUia);
    try {
      await client.uiaRequestBackground<void>((auth) async {
        if (auth != null) await windDown();
        await client.deactivateAccount(auth: auth, erase: true);
      });
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
    await client.clear(reason: SessionClearReason.logout);
  }
}

class _ConfirmDeletionDialog extends StatefulWidget {
  final String username;
  const _ConfirmDeletionDialog({required this.username});

  @override
  State<_ConfirmDeletionDialog> createState() => _ConfirmDeletionDialogState();
}

class _ConfirmDeletionDialogState extends State<_ConfirmDeletionDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _controller.text.trim() == widget.username;
    return AlertDialog(
      title: const Text('Confirm deletion'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Type your username to confirm: ${widget.username}'),
          const SizedBox(height: 12),
          TextField(
            autofillHints: null,
            controller: _controller,
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
          onPressed: matches ? () => Navigator.of(context).pop(true) : null,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}
