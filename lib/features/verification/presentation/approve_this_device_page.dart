import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/encryption.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/security/account_security_status.dart';
import '../../../core/ui/confirm_dialog.dart';
import '../../../core/ui/notice.dart';
import '../../../core/ui/step_hero.dart';
import '../../../core/ui/step_layout.dart';
import '../../settings/presentation/secure_backup_page.dart';
import 'start_verification.dart';

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
    final l10n = context.l10n;
    final ownKeys = client.userDeviceKeys[client.userID];
    if (ownKeys == null) {
      ScaffoldMessenger.of(context).say(l10n.verificationNoOtherDevices);
      return;
    }
    setState(() => _starting = true);
    final verification = await startAndOpenVerification(
      context,
      ownKeys.startVerification,
      label: 'start device approval',
      failed: l10n.verificationCouldNotStart,
      isOwnDevice: true,
    );
    if (!mounted) return;
    setState(() => _starting = false);
    if (verification?.state == KeyVerificationState.done) _finish();
  }

  Future<void> _startOver() async {
    final l10n = context.l10n;
    final confirmed = await confirm(
      context,
      title: l10n.verificationStartOverTitle,
      body: l10n.verificationStartOverBody,
      confirmLabel: l10n.verificationStartOver,
      tone: ConfirmTone.destructive,
    );
    if (!confirmed || !mounted) return;
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
