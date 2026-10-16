import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/account_security_status.dart';
import '../../../core/security/security_providers.dart';
import '../../verification/presentation/approve_this_device_page.dart';
import 'active_sessions_page.dart';
import 'secure_backup_page.dart';

Future<void> pushSecurityPage(
  BuildContext context,
  WidgetRef ref,
  Widget page,
) async {
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  if (context.mounted) ref.invalidate(accountSecurityFactsProvider);
}

Future<void> runSecurityStatusAction(
  BuildContext context,
  WidgetRef ref,
  AccountSecurityStatus status,
) async {
  final page = switch (status) {
    AccountSecurityStatus.noRecovery => const SecureBackupPage(),
    AccountSecurityStatus.deviceLocked => const ApproveThisDevicePage(),
    AccountSecurityStatus.deviceWaiting => const ActiveSessionsPage(),
    AccountSecurityStatus.recoveryStale => const SecureBackupPage(
      autoRestoreExisting: true,
    ),
    AccountSecurityStatus.protected => null,
  };
  if (page != null) await pushSecurityPage(context, ref, page);
}
