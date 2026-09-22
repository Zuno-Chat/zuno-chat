import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import 'change_password_dialog.dart';

const _avatarMaxDimension = 512;

const _rowSpinner = SizedBox(
  width: 20,
  height: 20,
  child: CircularProgressIndicator(strokeWidth: 2),
);

enum _AvatarAction { camera, gallery, remove }

class AccountSettingsPage extends ConsumerStatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  ConsumerState<AccountSettingsPage> createState() =>
      _AccountSettingsPageState();
}

class _AccountSettingsPageState extends ConsumerState<AccountSettingsPage> {
  CachedProfileInformation? _profile;
  bool _savingName = false;
  bool _savingAvatar = false;
  String? _profileError;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final client = ref.read(matrixClientProvider);
    try {
      final profile = await client.getUserProfile(client.userID!);
      if (!mounted) return;
      setState(() => _profile = profile);
    } catch (e) {
      if (mounted) setState(() => _profileError = e.toString());
    }
  }

  Future<void> _editDisplayName() async {
    final newName = await showDialog<String>(
      context: context,
      builder: (context) =>
          _EditDisplayNameDialog(initialName: _profile?.displayname ?? ''),
    );
    if (newName == null || !mounted) return;

    final client = ref.read(matrixClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingName = true);
    try {
      await client.setProfileField(client.userID!, 'displayname', {
        'displayname': newName,
      });
      await _loadProfile();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Display name updated')),
        );
      }
    } catch (e) {
      logCaught('update display name', e);
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Display name not saved. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _changeAvatar() async {
    final action = await showModalBottomSheet<_AvatarAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.of(context).pop(_AvatarAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(context).pop(_AvatarAction.gallery),
            ),
            if (_profile?.avatarUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () => Navigator.of(context).pop(_AvatarAction.remove),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    final client = ref.read(matrixClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingAvatar = true);
    try {
      if (action == _AvatarAction.remove) {
        await client.setAvatar(null);
      } else {
        final picked = await ImagePicker().pickImage(
          source: action == _AvatarAction.camera
              ? ImageSource.camera
              : ImageSource.gallery,
          imageQuality: 90,
        );
        if (picked == null) return;
        final shrunk = await MatrixImageFile.shrink(
          bytes: await picked.readAsBytes(),
          name: picked.name,
          maxDimension: _avatarMaxDimension,
          nativeImplementations: client.nativeImplementations,
        );
        await client.setAvatar(shrunk);
      }
      await _loadProfile();
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('Photo updated')));
      }
    } catch (e) {
      logCaught('update profile photo', e);
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Photo not saved. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingAvatar = false);
    }
  }

  Future<void> _copyUsername(String userId) async {
    await Clipboard.setData(ClipboardData(text: userId));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Username copied')));
    }
  }

  Future<void> _changePassword() async {
    final client = ref.read(matrixClientProvider);
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => ChangePasswordDialog(
        username: client.userID?.localpart ?? '',
        onSubmit: (current, next) async {
          try {
            await client.changePassword(next, oldPassword: current);
          } catch (e) {
            logCaught('change password', e);
            rethrow;
          }
        },
      ),
    );
    if (changed != true || !mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Password changed')));
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(matrixClientProvider);
    final displayName = _profile?.displayname;
    final userId = client.userID;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: CardListView(
        children: [
          CardGroup(
            title: 'Profile',
            children: [
              if (_profileError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    _profileError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ListTile(
                leading: MxcAvatar(
                  client: client,
                  avatarUrl: _profile?.avatarUrl,
                  fallbackText: displayName ?? userId ?? '?',
                  radius: 20,
                ),
                title: const Text('Profile picture'),
                trailing: _savingAvatar
                    ? _rowSpinner
                    : const Icon(Icons.chevron_right_outlined),
                onTap: _savingAvatar ? null : _changeAvatar,
              ),
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Display name'),
                subtitle: Text(
                  displayName == null || displayName.isEmpty
                      ? 'Not set'
                      : displayName,
                ),
                trailing: _savingName
                    ? _rowSpinner
                    : const Icon(Icons.chevron_right_outlined),
                onTap: _savingName ? null : _editDisplayName,
              ),
              ListTile(
                leading: const Icon(Icons.alternate_email_outlined),
                title: const Text('Username'),
                subtitle: Text(userId == null ? '' : withoutServer(userId)),
                trailing: const Icon(Icons.copy_outlined),
                onTap: userId == null
                    ? null
                    : () => _copyUsername(withoutServer(userId)),
              ),
            ],
          ),
          CardGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.password_outlined),
                title: const Text('Change password'),
                onTap: _changePassword,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditDisplayNameDialog extends StatefulWidget {
  final String initialName;
  const _EditDisplayNameDialog({required this.initialName});

  @override
  State<_EditDisplayNameDialog> createState() => _EditDisplayNameDialogState();
}

class _EditDisplayNameDialogState extends State<_EditDisplayNameDialog> {
  late final _name = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Display name'),
      content: TextField(
        autofillHints: null,
        controller: _name,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Display name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
