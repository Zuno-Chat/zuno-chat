import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/encryption.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/security/account_security_status.dart';
import '../../../core/ui/step_hero.dart';
import '../../../core/ui/step_layout.dart';
import '../../settings/presentation/secure_backup_page.dart';
import 'verification_page.dart';

typedef RecoveryOpener = Future<void> Function(
  BuildContext context, {
  required bool restoreExisting,
});

Future<void> openSecureBackup(
  BuildContext context, {
  required bool restoreExisting,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => SecureBackupPage(autoRestoreExisting: restoreExisting),
  ),
);

class ApproveThisDevicePage extends ConsumerStatefulWidget {
  final VoidCallback? onFinished;
  final bool showStartOver;
  final RecoveryOpener openRecovery;

  const ApproveThisDevicePage({
    this.onFinished,
    this.showStartOver = false,
    this.openRecovery = openSecureBackup,
    super.key,
  });

  @override
  ConsumerState<ApproveThisDevicePage> createState() =>
      _ApproveThisDevicePageState();
}

class _ApproveThisDevicePageState extends ConsumerState<ApproveThisDevicePage> {
  bool _starting = false;

  void _finish() {
    final onFinished = widget.onFinished;
    if (onFinished != null) {
      onFinished();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _approveFromOtherDevice() async {
    final client = ref.read(matrixClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final ownKeys = client.userDeviceKeys[client.userID];
    if (ownKeys == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.verificationNoOtherDevices)),
      );
      return;
    }
    setState(() => _starting = true);
    try {
      final keyVerification = await ownKeys.startVerification();
      if (!mounted) {
        unawaited(
          runBestEffort(
            () => keyVerification.cancel('m.user'),
            label: 'cancel unattended device approval',
          ),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerificationPage(
            keyVerification: keyVerification,
            isOwnDevice: true,
          ),
        ),
      );
      if (mounted && keyVerification.state == KeyVerificationState.done) {
        _finish();
      }
    } catch (e, s) {
      reportCaught('start device approval', e, s);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.verificationCouldNotStart)),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _startOver() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.verificationStartOverTitle),
        content: Text(context.l10n.verificationStartOverBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.verificationStartOver),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _openRecovery(restoreExisting: false);
  }

  Future<void> _useRecoveryCode() => _openRecovery(restoreExisting: true);

  Future<void> _openRecovery({required bool restoreExisting}) async {
    await widget.openRecovery(context, restoreExisting: restoreExisting);
    if (!mounted) return;
    final facts = await accountSecurityFactsOf(ref.read(matrixClientProvider));
    if (mounted && facts.thisDeviceHasIdentityKeys) _finish();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.verificationApproveTitle)),
      body: SafeArea(
        child: StepLayout(
          hero: const StepHero(icon: Icons.phonelink_lock_outlined),
          title: l10n.verificationApproveHeading,
          body: l10n.verificationApproveBody,
          actionsFollowContent: true,
          actions: [
            FilledButton.icon(
              onPressed: _starting ? null : _approveFromOtherDevice,
              icon: const Icon(Icons.qr_code_scanner_outlined),
              label: Text(l10n.verificationApproveFromOther),
            ),
            OutlinedButton(
              onPressed: _starting ? null : _useRecoveryCode,
              child: Text(l10n.securityEnterRecoveryCode),
            ),
            if (widget.showStartOver)
              TextButton(
                onPressed: _starting ? null : _startOver,
                child: Text(l10n.verificationLostCode),
              ),
            TextButton(onPressed: _finish, child: Text(l10n.commonNotNow)),
          ],
        ),
      ),
    );
  }
}
