import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/security/account_security_status.dart';
import '../../settings/presentation/secure_backup_page.dart';
import 'verification_page.dart';

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
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.verificationSetUpRecoveryTitle),
        content: Text(context.l10n.verificationSetUpRecoveryBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonNotNow),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonContinue),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;
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
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.verificationTheyHaveNoRecovery)),
    );
    return;
  }

  try {
    final keyVerification = await keys.startVerification();
    if (!context.mounted) {
      unawaited(
        runBestEffort(
          () => keyVerification.cancel('m.user'),
          label: 'cancel unattended verification',
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VerificationPage(
          keyVerification: keyVerification,
          picturesFirst: picturesFirst,
        ),
      ),
    );
  } catch (e, s) {
    reportCaught('start verification', e, s);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.verificationCouldNotStart)),
    );
  }
}

bool canConfirmPerson(Client client, String userId) =>
    userId != client.userID && client.userDeviceKeys[userId]?.masterKey != null;
