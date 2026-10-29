import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/active_call_provider.dart';
import '../../../core/errors/best_effort.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/location/live_location_sharing.dart';
import '../../../core/matrix/auth_error_message.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/sign_out.dart';
import '../../../core/matrix/uia_cancel.dart';
import '../../../core/push/delivery/notification_delivery.dart';
import '../../../core/security/zuno_text_field.dart';
import '../../../core/ui/confirm_dialog.dart';
import '../../../core/ui/danger_tile.dart';
import '../../../core/ui/notice.dart';
import 'uia_password_prompt.dart';

class DeleteAccountTile extends ConsumerStatefulWidget {
  const DeleteAccountTile({super.key});

  @override
  ConsumerState<DeleteAccountTile> createState() => _DeleteAccountTileState();
}

class _DeleteAccountTileState extends ConsumerState<DeleteAccountTile> {
  @override
  Widget build(BuildContext context) => DangerTile(
    icon: Icons.delete_forever_outlined,
    label: context.l10n.settingsDeleteAccount,
    onTap: _start,
  );

  Future<void> _start() async {
    final l10n = context.l10n;
    final proceed = await confirm(
      context,
      title: l10n.settingsDeleteAccountWarningTitle,
      body: l10n.settingsDeleteAccountWarningBody,
      confirmLabel: l10n.commonContinue,
      tone: ConfirmTone.destructive,
    );
    if (!proceed || !mounted) return;

    final matches = await _confirmTypedId();
    if (matches != true || !mounted) return;

    await _deactivate();
  }

  Future<bool?> _confirmTypedId() {
    final userId = ref.read(matrixClientProvider).userID ?? '';
    final username = userId.localpart ?? userId;
    return showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmDeletionDialog(username: username),
    );
  }

  Future<void> _handleUia(UiaRequest uia) => answerUiaWithPassword(
    context,
    uia,
    userId: ref.read(matrixClientProvider).userID!,
    title: context.l10n.settingsDeleteAccountUiaTitle,
    message: _windDownNotice(),
  );

  String? _windDownNotice() {
    final l10n = context.l10n;
    final inCall = ref.read(activeCallProvider) != null;
    final sharing = ref.read(liveLocationSharingProvider).shares.value;
    return switch ((inCall, sharing.isNotEmpty)) {
      (true, true) => l10n.settingsDeleteAccountWindDownCallAndLocation,
      (true, false) => l10n.settingsDeleteAccountWindDownCall,
      (false, true) => l10n.settingsDeleteAccountWindDownLocation,
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
    } catch (e, s) {
      if (isUiaCancel(e)) return;
      if (!isPasswordRefusal(e)) reportCaught('delete account', e, s);
      if (!mounted) return;
      messenger.say(deactivateAccountErrorMessage(context.l10n, e));
      return;
    } finally {
      unawaited(uiaSub.cancel());
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
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.settingsDeleteAccountConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingsDeleteAccountTypeUsername(widget.username)),
          const SizedBox(height: 12),
          ZunoTextField(
            autofillHints: null,
            controller: _controller,
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => TextButton(
            onPressed: _controller.text.trim() == widget.username
                ? () => Navigator.of(context).pop(true)
                : null,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.settingsDeleteAccount),
          ),
        ),
      ],
    );
  }
}
