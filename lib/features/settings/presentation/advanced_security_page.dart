import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/display_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import 'key_backup_management_page.dart';
import 'secure_backup_page.dart';
import 'session_key_format.dart';
import 'settings_widgets.dart';

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

  void _copyToClipboard(@displayText String copiedMessage, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(copiedMessage)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final client = ref.watch(matrixClientProvider);
    final encryption = client.encryption;
    final crossSigningEnabled = encryption?.crossSigning.enabled ?? false;
    final backupEnabled = encryption?.keyManager.enabled ?? false;

    final crossSigningSubtitle = switch ((
      crossSigningEnabled,
      _crossSigningKeysCached,
    )) {
      (false, _) => l10n.settingsAdvancedCrossSigningNotSetUp,
      (true, true) => l10n.settingsAdvancedCrossSigningKeysHere,
      (true, false) => l10n.settingsAdvancedCrossSigningKeysNotHere,
    };

    final deviceName = client.deviceName;
    final deviceId = client.deviceID ?? l10n.settingsAdvancedUnknown;
    final sessionKey = formatSessionKey(client.fingerprintKey);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAdvancedTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(l10n.settingsAdvancedIntro),
          ),
          SettingsSectionHeader(l10n.settingsAdvancedCryptography),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(l10n.settingsAdvancedCrossSigning),
            subtitle: Text(crossSigningSubtitle),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(l10n.settingsAdvancedSessionName),
            subtitle: Text(
              deviceName == null || deviceName.isEmpty
                  ? l10n.settingsAdvancedUnnamedSession
                  : deviceName,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.fingerprint_outlined),
            title: Text(l10n.settingsAdvancedSessionId),
            subtitle: Text(deviceId),
            trailing: IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: l10n.settingsAdvancedCopySessionId,
              onPressed: () => _copyToClipboard(
                l10n.settingsAdvancedSessionIdCopied,
                deviceId,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: Text(l10n.settingsAdvancedSessionKey),
            subtitle: Text(sessionKey),
            trailing: IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: l10n.settingsAdvancedCopySessionKey,
              onPressed: () => _copyToClipboard(
                l10n.settingsAdvancedSessionKeyCopied,
                client.fingerprintKey,
              ),
            ),
          ),
          const Divider(),
          SettingsSectionHeader(l10n.settingsAdvancedSecretStorage),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.settingsAdvancedSecretStorageIntro,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: Text(l10n.settingsAdvancedUseSecurityKey),
            subtitle: Text(l10n.settingsAdvancedUseSecurityKeySubtitle),
            trailing: const Icon(Icons.chevron_right_outlined),
            onTap: () => _openSecureBackup(SecureBackupMode.key),
          ),
          ListTile(
            leading: const Icon(Icons.password_outlined),
            title: Text(l10n.settingsAdvancedUseSecurityPhrase),
            subtitle: Text(l10n.settingsAdvancedUseSecurityPhraseSubtitle),
            trailing: const Icon(Icons.chevron_right_outlined),
            onTap: () => _openSecureBackup(SecureBackupMode.phrase),
          ),
          const Divider(),
          SettingsSectionHeader(l10n.settingsAdvancedKeysManagement),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: Text(l10n.settingsAdvancedManageKeyBackup),
            subtitle: Text(
              backupEnabled
                  ? l10n.settingsAdvancedKeyBackupActive
                  : l10n.settingsAdvancedKeyBackupNotSetUp,
            ),
            trailing: const Icon(Icons.chevron_right_outlined),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const KeyBackupManagementPage(),
              ),
            ),
          ),
          ComingSoonTile(
            icon: Icons.upload_file_outlined,
            title: l10n.settingsAdvancedExportKeys,
            subtitle: l10n.settingsAdvancedExportKeysSubtitle,
          ),
          ComingSoonTile(
            icon: Icons.download_outlined,
            title: l10n.settingsAdvancedImportKeys,
            subtitle: l10n.settingsAdvancedImportKeysSubtitle,
          ),
        ],
      ),
    );
  }
}
