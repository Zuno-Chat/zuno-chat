import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/settings/app_preferences_provider.dart';
import 'key_backup_management_page.dart';
import 'secure_backup_page.dart';
import 'session_key_format.dart';
import 'settings_widgets.dart';
import 'temporary_session_token_tile.dart';

class AdvancedSecurityPage extends ConsumerStatefulWidget {
  const AdvancedSecurityPage({super.key});

  @override
  ConsumerState<AdvancedSecurityPage> createState() =>
      _AdvancedSecurityPageState();
}

class _AdvancedSecurityPageState extends ConsumerState<AdvancedSecurityPage> {
  bool _crossSigningKeysCached = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCrossSigningCacheStatus());
  }

  Future<void> _loadCrossSigningCacheStatus() async {
    final cached =
        await ref
            .read(matrixClientProvider)
            .encryption
            ?.crossSigning
            .isCached() ??
        false;
    if (mounted) setState(() => _crossSigningKeysCached = cached);
  }

  Future<void> _openSecureBackup(SecureBackupMode mode) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SecureBackupPage(mode: mode)));
    if (mounted) {
      setState(() {});
      unawaited(_loadCrossSigningCacheStatus());
    }
  }

  void _copyToClipboard(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label copied')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final encryptToVerifiedOnly = ref.watch(
      encryptToVerifiedSessionsOnlyProvider,
    );
    final client = ref.watch(matrixClientProvider);
    final encryption = client.encryption;
    final crossSigningEnabled = encryption?.crossSigning.enabled ?? false;
    final backupEnabled = encryption?.keyManager.enabled ?? false;

    final ownDevices =
        client.userDeviceKeys[client.userID]?.deviceKeys.values ?? [];
    final anyVerifiedDevice = ownDevices.any(
      (d) => d.deviceId != client.deviceID && d.directVerified,
    );

    final crossSigningSubtitle = switch ((
      crossSigningEnabled,
      _crossSigningKeysCached,
    )) {
      (false, _) => 'Not set up',
      (true, true) => 'Enabled · Private keys are on this device',
      (true, false) => 'Enabled · Private keys are not on this device',
    };

    final deviceName = client.deviceName;
    final deviceId = client.deviceID ?? 'Unknown';
    final sessionKey = formatSessionKey(client.fingerprintKey);

    return Scaffold(
      appBar: AppBar(title: const Text('Advanced')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              "The raw mechanics behind recovery and device approval. You "
              "don't need any of this for day-to-day use.",
            ),
          ),
          const SettingsSectionHeader('Cryptography'),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('Cross-signing'),
            subtitle: Text(crossSigningSubtitle),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Session name'),
            subtitle: Text(
              deviceName == null || deviceName.isEmpty
                  ? 'Unnamed session'
                  : deviceName,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.fingerprint_outlined),
            title: const Text('Session ID'),
            subtitle: Text(deviceId),
            trailing: IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: 'Copy session ID',
              onPressed: () => _copyToClipboard('Session ID', deviceId),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('Session key'),
            subtitle: Text(sessionKey),
            trailing: IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: 'Copy session key',
              onPressed: () =>
                  _copyToClipboard('Session key', client.fingerprintKey),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.gpp_good_outlined),
            title: const Text('Encrypt to verified sessions only'),
            subtitle: Text(
              anyVerifiedDevice
                  ? "Don't send encrypted messages to other sessions from "
                        "this session until they're verified"
                  : 'Unavailable until you have approved another device — '
                        'turning this on now would stop your messages '
                        'reaching anyone at all, including you.',
            ),
            value: encryptToVerifiedOnly && anyVerifiedDevice,
            onChanged: anyVerifiedDevice
                ? (value) => ref
                      .read(encryptToVerifiedSessionsOnlyProvider.notifier)
                      .set(value)
                : null,
          ),
          const TemporarySessionTokenTile(),
          const Divider(),
          const SettingsSectionHeader('Secret storage'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Alternatives to the generated recovery code — a raw security '
              'key to paste between clients, or a phrase you choose '
              'yourself. Setting up either one replaces your current '
              'recovery code.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('Use a security key'),
            subtitle: const Text(
              'Generate a raw key to store somewhere safe, like a password '
              'manager',
            ),
            trailing: const Icon(Icons.chevron_right_outlined),
            onTap: () => _openSecureBackup(SecureBackupMode.key),
          ),
          ListTile(
            leading: const Icon(Icons.password_outlined),
            title: const Text('Use a security phrase'),
            subtitle: const Text('Choose a secret phrase of your own'),
            trailing: const Icon(Icons.chevron_right_outlined),
            onTap: () => _openSecureBackup(SecureBackupMode.phrase),
          ),
          const Divider(),
          const SettingsSectionHeader('Cryptography keys management'),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Manage key backup'),
            subtitle: Text(backupEnabled ? 'Active' : 'Not set up'),
            trailing: const Icon(Icons.chevron_right_outlined),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const KeyBackupManagementPage(),
              ),
            ),
          ),
          const ComingSoonTile(
            icon: Icons.upload_file_outlined,
            title: 'Export E2E room keys',
            subtitle: 'Save an encrypted copy of your room keys to a file',
          ),
          const ComingSoonTile(
            icon: Icons.download_outlined,
            title: 'Import E2E room keys',
            subtitle: 'Restore room keys from a previously exported file',
          ),
        ],
      ),
    );
  }
}
