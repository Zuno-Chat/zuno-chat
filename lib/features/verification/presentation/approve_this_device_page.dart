import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/ui/step_hero.dart';
import '../../../core/ui/step_layout.dart';
import '../../settings/presentation/secure_backup_page.dart';
import 'verification_page.dart';

class ApproveThisDevicePage extends ConsumerStatefulWidget {
  final VoidCallback? onFinished;
  final bool showStartOver;

  const ApproveThisDevicePage({
    this.onFinished,
    this.showStartOver = false,
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
    final ownKeys = client.userDeviceKeys[client.userID];
    if (ownKeys == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not find your other devices yet.')),
      );
      return;
    }
    setState(() => _starting = true);
    try {
      final keyVerification = await ownKeys.startVerification();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerificationPage(
            keyVerification: keyVerification,
            isOwnDevice: true,
          ),
        ),
      );
      if (mounted) _finish();
    } catch (e) {
      logCaught('start device approval', e);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not start. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _startOver() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start over with a new code?'),
        content: const Text(
          'Your current recovery code stops working, your other devices need '
          'approving again, and messages older than this device stay locked. '
          'Nobody can undo this. Only do it if the old code is gone for good.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Start over'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SecureBackupPage(autoRestoreExisting: false),
      ),
    );
    if (mounted) _finish();
  }

  Future<void> _useRecoveryCode() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SecureBackupPage(autoRestoreExisting: true),
      ),
    );
    if (mounted) _finish();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Approve this device')),
      body: SafeArea(
        child: StepLayout(
          hero: const StepHero(icon: Icons.phonelink_lock_outlined),
          title: 'Older messages are not here yet',
          body: 'Approve this device and your message history comes back.',
          actionsFollowContent: true,
          actions: [
            FilledButton.icon(
              onPressed: _starting ? null : _approveFromOtherDevice,
              icon: const Icon(Icons.qr_code_scanner_outlined),
              label: const Text('Approve from another device'),
            ),
            OutlinedButton(
              onPressed: _starting ? null : _useRecoveryCode,
              child: const Text('Enter recovery code'),
            ),
            if (widget.showStartOver)
              TextButton(
                onPressed: _starting ? null : _startOver,
                child: const Text('Lost the code? Start over'),
              ),
            TextButton(onPressed: _finish, child: const Text('Not now')),
          ],
        ),
      ),
    );
  }
}
