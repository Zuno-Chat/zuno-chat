import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/app_language.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/auth_error_message.dart';
import '../../../core/matrix/avatar_photo.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/own_profile.dart';
import '../../../core/platform/app_settings_opener.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import '../../../core/ui/edit_text_dialog.dart';
import '../../../core/ui/inline_feedback.dart';
import '../../../core/ui/notice.dart';
import '../../../core/ui/sheet.dart';
import 'change_password_dialog.dart';

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
    final l10n = context.l10n;
    final currentName = _profile?.displayname ?? '';
    final newName = await showEditTextDialog(
      context,
      title: l10n.settingsAccountDisplayName,
      initialValue: currentName,
      allowEmpty: false,
    );
    if (newName == null || newName == currentName || !mounted) return;

    final client = ref.read(matrixClientProvider);
    setState(() => _savingName = true);
    await attempt(
      context,
      () async {
        await setOwnDisplayName(client, newName);
        await _loadProfile(fresh: true);
      },
      label: 'update display name',
      failed: l10n.settingsAccountDisplayNameNotSaved,
      succeeded: l10n.settingsAccountDisplayNameUpdated,
    );
    if (mounted) setState(() => _savingName = false);
  }

  Future<void> _changeAvatar() async {
    final action = await chooseAvatarAction(
      context,
      canRemove: _profile?.avatarUrl != null,
    );
    if (action == null || !mounted) return;

    final client = ref.read(matrixClientProvider);
    setState(() => _savingAvatar = true);
    await applyAvatarAction(
      context,
      action,
      nativeImplementations: client.nativeImplementations,
      apply: (photo) async {
        await client.setAvatar(photo);
        await _loadProfile(fresh: true);
      },
      label: 'update profile photo',
    );
    if (mounted) setState(() => _savingAvatar = false);
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

    ScaffoldMessenger.of(context)
        .say(context.l10n.settingsAccountPasswordChanged);
  }

  Future<void> _chooseLanguage(AppLanguage current) async {
    final l10n = context.l10n;
    final chosen = await showChoiceSheet<String>(
      context,
      current: current.tag == null ? '' : current.chosen?.tag,
      choices: [
        SheetChoice('', label: l10n.settingsLanguageDevice),
        for (final option in current.options)
          SheetChoice(
            option.tag,
            label: lookupAppLocalizations(option.locale).languageNativeName,
          ),
      ],
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
        final chosen = language.chosen;
        return ListTile(
          leading: const Icon(Icons.language_outlined),
          title: Text(l10n.settingsLanguage),
          subtitle: Text(switch ((language.tag, chosen)) {
            (null, _) => l10n.settingsLanguageDevice,
            (_, null) => l10n.languageNativeName,
            (_, final option?) => lookupAppLocalizations(
              option.locale,
            ).languageNativeName,
          }),
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
                  child: InlineError(l10n.settingsAccountProfileLoadFailed),
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
                    ? const InlineSpinner()
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
                    ? const InlineSpinner()
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
                    : () => ScaffoldMessenger.of(context).copy(
                        withoutServer(userId),
                        copied: l10n.settingsAccountUsernameCopied,
                      ),
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
