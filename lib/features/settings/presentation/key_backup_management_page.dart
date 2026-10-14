import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/errors/connection_error.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/matrix_client_provider.dart';

class KeyBackupManagementPage extends ConsumerStatefulWidget {
  const KeyBackupManagementPage({super.key});

  @override
  ConsumerState<KeyBackupManagementPage> createState() =>
      _KeyBackupManagementPageState();
}

class _KeyBackupManagementPageState
    extends ConsumerState<KeyBackupManagementPage> {
  bool _loading = true;
  bool _loadFailed = false;
  GetRoomKeysVersionCurrentResponse? _info;
  bool _cachedOnThisDevice = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final client = ref.read(matrixClientProvider);
    try {
      final info = await _currentBackup(client);
      final cached = await client.encryption?.keyManager.isCached() ?? false;
      if (!mounted) return;
      setState(() {
        _info = info;
        _cachedOnThisDevice = cached;
        _loadFailed = false;
      });
    } catch (e, s) {
      reportCaught('load key backup', e, s);
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<GetRoomKeysVersionCurrentResponse?> _currentBackup(
    Client client,
  ) async {
    try {
      return await client.getRoomKeysVersionCurrent();
    } on MatrixException catch (e) {
      if (e.errcode != 'M_NOT_FOUND') rethrow;
      return null;
    }
  }

  Future<void> _deleteBackup() async {
    final info = _info;
    if (info == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsKeyBackupDeleteTitle),
        content: Text(context.l10n.settingsKeyBackupDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() => _deleting = true);
    try {
      await ref.read(matrixClientProvider).deleteRoomKeysVersion(info.version);
    } catch (e, s) {
      reportCaught('delete key backup', e, s);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failureMessage(l10n, e, failed: l10n.settingsKeyBackupDeleteFailed),
          ),
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final info = _info;
    final errorColor = Theme.of(context).colorScheme.error;
    Widget note(String text) => Padding(
      padding: const EdgeInsets.only(top: 96),
      child: Center(child: Text(text)),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsKeyBackupTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (_loadFailed)
                    note(l10n.settingsKeyBackupLoadFailed)
                  else if (info == null)
                    note(l10n.settingsKeyBackupNone)
                  else ...[
                    ListTile(
                      leading: const Icon(Icons.backup_outlined),
                      title: Text(l10n.commonStatus),
                      subtitle: Text(
                        _cachedOnThisDevice
                            ? l10n.settingsKeyBackupActiveRestorable
                            : l10n.settingsKeyBackupActiveNotRestorable,
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.key_outlined),
                      title: Text(l10n.settingsKeyBackupKeysBackedUp),
                      subtitle: Text(l10n.commonCount(info.count)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.numbers_outlined),
                      title: Text(l10n.commonVersion),
                      subtitle: Text(info.version),
                    ),
                    ListTile(
                      leading: const Icon(Icons.lock_outlined),
                      title: Text(l10n.settingsKeyBackupAlgorithm),
                      subtitle: Text(info.algorithm.name),
                    ),
                    const Divider(),
                    ListTile(
                      leading: Icon(Icons.delete_outline, color: errorColor),
                      title: Text(
                        l10n.settingsKeyBackupDelete,
                        style: TextStyle(color: errorColor),
                      ),
                      trailing: _deleting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                      onTap: _deleting ? null : _deleteBackup,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
