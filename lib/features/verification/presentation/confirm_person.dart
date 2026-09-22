import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/security/account_security_status.dart';
import '../../../core/security/security_providers.dart';
import '../../settings/presentation/secure_backup_page.dart';
import 'verification_page.dart';

Future<void> confirmPerson(
  BuildContext context,
  WidgetRef ref,
  String userId, {
  Future<void> Function(BuildContext context)? setUpRecovery,
}) async {
  final client = ref.read(matrixClientProvider);
  final messenger = ScaffoldMessenger.of(context);

  final facts = await accountSecurityFactsOf(client);
  if (!facts.recoveryExists || !facts.thisDeviceHasIdentityKeys) {
    if (!context.mounted) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set up recovery first'),
        content: const Text(
          'Before you can confirm someone else, this device needs its own '
          'recovery set up. It only takes a moment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
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
      const SnackBar(
        content: Text(
          'They have not set up recovery yet, so there is nothing to confirm.',
        ),
      ),
    );
    return;
  }

  try {
    final keyVerification = await keys.startVerification();
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VerificationPage(keyVerification: keyVerification),
      ),
    );
    if (client.userDeviceKeys[userId]?.masterKey?.directVerified ?? false) {
      await rememberConfirmedIdentity(
        ref.read(confirmedIdentityStoreProvider),
        client,
        userId,
      );
    }
  } catch (e) {
    logCaught('start verification', e);
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not start. Try again.')),
    );
  }
}

bool canConfirmPerson(Client client, String userId) =>
    userId != client.userID && client.userDeviceKeys[userId]?.masterKey != null;
