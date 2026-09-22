import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

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
    setState(() => _loading = true);
    GetRoomKeysVersionCurrentResponse? info;
    try {
      info = await client.getRoomKeysVersionCurrent();
    } on MatrixException catch (e) {
      if (e.errcode != 'M_NOT_FOUND') rethrow;
      info = null;
    }
    final cached = await client.encryption?.keyManager.isCached() ?? false;
    if (!mounted) return;
    setState(() {
      _info = info;
      _cachedOnThisDevice = cached;
      _loading = false;
    });
  }

  Future<void> _deleteBackup() async {
    final info = _info;
    if (info == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete key backup?'),
        content: const Text(
          'This deletes the online backup of your encrypted message keys. '
          "Devices that haven't already synced these keys another way "
          "won't be able to recover them. This doesn't change Secure "
          'backup itself — a new backup can be created again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _deleting = true);
    try {
      await ref.read(matrixClientProvider).deleteRoomKeysVersion(info.version);
      await _refresh();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final errorColor = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: const Text('Manage key backup')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: info == null
                    ? const [
                        Padding(
                          padding: EdgeInsets.only(top: 96),
                          child: Center(
                            child: Text(
                              'No key backup set up on this account.',
                            ),
                          ),
                        ),
                      ]
                    : [
                        ListTile(
                          leading: const Icon(Icons.backup_outlined),
                          title: const Text('Status'),
                          subtitle: Text(
                            _cachedOnThisDevice
                                ? 'Active — this device can restore from it'
                                : "Active, but this device can't restore from it "
                                      '(set up Secure backup)',
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.key_outlined),
                          title: const Text('Keys backed up'),
                          subtitle: Text('${info.count}'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.numbers_outlined),
                          title: const Text('Version'),
                          subtitle: Text(info.version),
                        ),
                        ListTile(
                          leading: const Icon(Icons.lock_outlined),
                          title: const Text('Algorithm'),
                          subtitle: Text(info.algorithm.name),
                        ),
                        const Divider(),
                        ListTile(
                          leading: Icon(
                            Icons.delete_outline,
                            color: errorColor,
                          ),
                          title: Text(
                            'Delete key backup',
                            style: TextStyle(color: errorColor),
                          ),
                          trailing: _deleting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : null,
                          onTap: _deleting ? null : _deleteBackup,
                        ),
                      ],
              ),
            ),
    );
  }
}
