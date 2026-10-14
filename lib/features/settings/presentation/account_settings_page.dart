import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/app_language.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/auth_error_message.dart';
import '../../../core/matrix/avatar_photo.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/picker_access.dart';
import '../../../core/platform/app_settings_opener.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import '../../../core/ui/sheet.dart';
import 'change_password_dialog.dart';

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
  bool _profileFailed = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile({bool fresh = false}) async {
    final client = ref.read(matrixClientProvider);
    try {
      final profile = await client.getUserProfile(
        client.userID!,
        maxCacheAge: fresh ? Duration.zero : const Duration(days: 1),
      );
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _profileFailed = false;
      });
    } catch (e, s) {
      reportCaught('load profile', e, s);
      if (mounted) {
        setState(() => _profileFailed = true);
      }
    }
  }

  Future<void> _editDisplayName() async {
    final currentName = _profile?.displayname ?? '';
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => _EditDisplayNameDialog(initialName: currentName),
    );
    if (newName == null || newName == currentName || !mounted) return;

    final client = ref.read(matrixClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingName = true);
    try {
      await client.setProfileField(client.userID!, 'displayname', {
        'displayname': newName,
      });
      await _loadProfile(fresh: true);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(context.l10n.settingsAccountDisplayNameUpdated),
          ),
        );
      }
    } catch (e, s) {
      reportCaught('update display name', e, s);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(context.l10n.settingsAccountDisplayNameNotSaved),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _changeAvatar() async {
    final action = await showSheet<_AvatarAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(context.l10n.commonTakePhoto),
              onTap: () => Navigator.of(context).pop(_AvatarAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(context.l10n.commonChooseFromGallery),
              onTap: () => Navigator.of(context).pop(_AvatarAction.gallery),
            ),
            if (_profile?.avatarUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(context.l10n.commonRemovePhoto),
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
        final shrunk = await prepareAvatarPhoto(
          await picked.readAsBytes(),
          name: picked.name,
          nativeImplementations: client.nativeImplementations,
        );
        await client.setAvatar(shrunk);
      }
      await _loadProfile(fresh: true);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.commonPhotoUpdated)),
        );
      }
    } catch (e, s) {
      if (!isPickerAccessDenied(e)) reportCaught('update profile photo', e, s);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.commonPhotoNotSaved)),
        );
      }
    } finally {
      if (mounted) setState(() => _savingAvatar = false);
    }
  }

  Future<void> _copyUsername(String userId) async {
    await Clipboard.setData(ClipboardData(text: userId));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settingsAccountUsernameCopied)),
      );
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
          } catch (e, s) {
            if (!isPasswordRefusal(e)) reportCaught('change password', e, s);
            rethrow;
          }
        },
      ),
    );
    if (changed != true || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.settingsAccountPasswordChanged)),
    );
  }

  Future<void> _chooseLanguage(AppLanguage current) async {
    final l10n = context.l10n;
    final chosen = await showSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: RadioGroup<String>(
          groupValue: current.locale?.languageCode ?? '',
          onChanged: (code) => Navigator.of(context).pop(code),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: Text(l10n.settingsLanguageDevice),
                value: '',
              ),
              for (final locale in AppLocalizations.supportedLocales)
                RadioListTile<String>(
                  title: Text(
                    lookupAppLocalizations(locale).languageNativeName,
                  ),
                  value: locale.languageCode,
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    try {
      await ref
          .read(appLanguageProvider.notifier)
          .set(chosen.isEmpty ? null : chosen);
    } catch (e, s) {
      reportCaught('set app language', e, s);
    }
  }

  Future<void> _openLanguageSettings() async {
    final open = ref.read(appSettingsOpenerProvider);
    if (View.of(context).platformDispatcher.locales.length > 1) {
      await open();
      return;
    }
    final l10n = context.l10n;
    final proceed = await showSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.settingsLanguage,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(l10n.settingsLanguageAddStep),
              const SizedBox(height: 8),
              Text(l10n.settingsLanguageChooseStep),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.settingsLanguageOpenSettings),
              ),
            ],
          ),
        ),
      ),
    );
    if (proceed == true) await open();
  }

  Widget? _languageRow(AppLocalizations l10n) {
    switch (ref.watch(platformCapabilitiesProvider).appLanguage) {
      case AppLanguageSetting.systemSettings:
        return ListTile(
          leading: const Icon(Icons.language_outlined),
          title: Text(l10n.settingsLanguage),
          subtitle: Text(l10n.languageNativeName),
          trailing: const Icon(Icons.open_in_new),
          onTap: _openLanguageSettings,
        );
      case AppLanguageSetting.inApp:
        final language = ref.watch(appLanguageProvider).value;
        if (language == null) return null;
        final locale = language.locale;
        return ListTile(
          leading: const Icon(Icons.language_outlined),
          title: Text(l10n.settingsLanguage),
          subtitle: Text(
            locale == null
                ? l10n.settingsLanguageDevice
                : lookupAppLocalizations(locale).languageNativeName,
          ),
          trailing: const Icon(Icons.chevron_right_outlined),
          onTap: () => _chooseLanguage(language),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final languageRow = _languageRow(l10n);
    final client = ref.watch(matrixClientProvider);
    final displayName = _profile?.displayname;
    final userId = client.userID;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAccountTitle)),
      body: CardListView(
        children: [
          CardGroup(
            title: l10n.settingsAccountProfile,
            children: [
              if (_profileFailed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    l10n.settingsAccountProfileLoadFailed,
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
                  toneSeed: userId ?? '',
                  radius: 20,
                ),
                title: Text(l10n.settingsAccountProfilePicture),
                trailing: _savingAvatar
                    ? _rowSpinner
                    : const Icon(Icons.chevron_right_outlined),
                onTap: _savingAvatar ? null : _changeAvatar,
              ),
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(l10n.settingsAccountDisplayName),
                subtitle: Text(
                  displayName == null || displayName.isEmpty
                      ? l10n.settingsAccountDisplayNameNotSet
                      : displayName,
                ),
                trailing: _savingName
                    ? _rowSpinner
                    : const Icon(Icons.chevron_right_outlined),
                onTap: _savingName ? null : _editDisplayName,
              ),
              ListTile(
                leading: const Icon(Icons.alternate_email_outlined),
                title: Text(l10n.commonUsername),
                subtitle: Text(userId == null ? '' : withoutServer(userId)),
                trailing: const Icon(Icons.copy_outlined),
                onTap: userId == null
                    ? null
                    : () => _copyUsername(withoutServer(userId)),
              ),
            ],
          ),
          if (languageRow != null) CardGroup(children: [languageRow]),
          CardGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.password_outlined),
                title: Text(l10n.settingsAccountChangePassword),
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
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.settingsAccountDisplayName),
      content: TextField(
        autofillHints: null,
        controller: _name,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.settingsAccountDisplayName),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.commonSave)),
      ],
    );
  }
}
