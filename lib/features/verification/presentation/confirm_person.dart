import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/security/account_security_status.dart';
import '../../../core/ui/confirm_dialog.dart';
import '../../../core/ui/notice.dart';
import '../../settings/presentation/secure_backup_page.dart';
import 'start_verification.dart';

Future<void> confirmPerson(
  BuildContext context,
  WidgetRef ref,
  String userId, {
  Future<void> Function(BuildContext context)? setUpRecovery,
  bool picturesFirst = false,
}) async {
  final client = ref.read(matrixClientProvider);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;

  final facts = await accountSecurityFactsOf(client);
  if (!facts.recoveryExists || !facts.thisDeviceHasIdentityKeys) {
    if (!context.mounted) return;
    final proceed = await confirm(
      context,
      title: l10n.verificationSetUpRecoveryTitle,
      body: l10n.verificationSetUpRecoveryBody,
      confirmLabel: l10n.commonContinue,
      cancelLabel: l10n.commonNotNow,
      tone: ConfirmTone.primary,
    );
    if (!proceed || !context.mounted) return;
    if (setUpRecovery != null) {
      await setUpRecovery(context);
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SecureBackupPage(
            autoRestoreExisting: facts.recoveryExists ? true : null,
          ),
        ),
      );
    }
    if (!context.mounted) return;
    final after = await accountSecurityFactsOf(client);
    if (!after.recoveryExists || !after.thisDeviceHasIdentityKeys) return;
  }

  final keys = client.userDeviceKeys[userId];
  if (keys == null || keys.masterKey == null) {
    messenger.say(l10n.verificationTheyHaveNoRecovery);
    return;
  }
  if (!context.mounted) return;

  await startAndOpenVerification(
    context,
    keys.startVerification,
    label: 'start verification',
    failed: l10n.verificationCouldNotStart,
    picturesFirst: picturesFirst,
  );
}

bool canConfirmPerson(Client client, String userId) =>
    userId != client.userID && client.userDeviceKeys[userId]?.masterKey != null;
