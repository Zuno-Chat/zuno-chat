import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/crash_reporting.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/own_profile.dart';
import '../../../core/matrix/sign_out.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/security/account_security_status.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import '../../../core/ui/circle_icon.dart';
import '../../../core/ui/danger_tile.dart';
import '../../feedback/presentation/feedback_sheet.dart';
import 'about_page.dart';
import 'account_settings_page.dart';
import 'chats_calls_settings_page.dart';
import 'data_storage_settings_page.dart';
import 'delete_account_tile.dart';
import 'notifications_settings_page.dart';
import 'secure_backup_page.dart';
import 'security_privacy_settings_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final client = ref.watch(matrixClientProvider);
    final capabilities = ref.watch(platformCapabilitiesProvider);
    final screenshotBlocking = capabilities.screenshotBlocking;
    final canChooseDelivery = capabilities.deliveryModes.length > 1;
    final paymentLinks = capabilities.externalPaymentLinks;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsPageTitle)),
      body: CardListView(
        children: [
          CardGroup(children: [_ProfileRow(client: client)]),
          CardGroup(
            children: [
              _CategoryTile(
                icon: Icons.notifications_outlined,
                title: l10n.settingsPageNotifications,
                subtitle: canChooseDelivery
                    ? l10n.settingsPageNotificationsDelivery
                    : l10n.settingsPageNotificationsMentions,
                page: const NotificationsSettingsPage(),
              ),
              _CategoryTile(
                icon: Icons.chat_bubble_outline,
                title: l10n.settingsPageChatsCalls,
                subtitle: l10n.settingsPageChatsCallsSubtitle,
                page: const ChatsCallsSettingsPage(),
              ),
              _CategoryTile(
                icon: Icons.data_usage_outlined,
                title: l10n.settingsPageDataStorage,
                subtitle: l10n.settingsPageDataStorageSubtitle,
                page: const DataStorageSettingsPage(),
              ),
            ],
          ),
          CardGroup(
            children: [
              _CategoryTile(
                icon: Icons.shield_outlined,
                title: l10n.settingsPageSecurity,
                subtitle: screenshotBlocking
                    ? l10n.settingsPageSecurityScreenshots
                    : l10n.settingsPageSecurityScreenContent,
                page: const SecurityPrivacySettingsPage(),
              ),
              _CategoryTile(
                icon: Icons.info_outline,
                title: l10n.settingsPageAbout,
                subtitle: paymentLinks
                    ? l10n.settingsPageAboutDonate
                    : l10n.settingsPageAboutTerms,
                page: const AboutPage(),
              ),
              if (ref.watch(sentryConfiguredProvider))
                ListTile(
                  leading: const CircleIcon(Icons.feedback_outlined),
                  title: Text(l10n.settingsPageSendFeedback),
                  onTap: () => showFeedbackSheet(context),
                ),
            ],
          ),
          CardGroup(
            children: [
              DangerTile(
                icon: Icons.logout_outlined,
                label: l10n.settingsSignOut,
                onTap: () => _confirmLogOut(context, ref),
              ),
              const DeleteAccountTile(),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogOut(BuildContext context, WidgetRef ref) async {
    final noRecovery =
        ref.read(accountSecurityStatusProvider).value ==
        AccountSecurityStatus.noRecovery;
    final navigator = Navigator.of(context);
    final l10n = context.l10n;

    final choice = await showDialog<_LogOutChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsPageSignOutTitle),
        actionsOverflowDirection: VerticalDirection.up,
        actionsOverflowButtonSpacing: 4,
        content: Text(
          noRecovery
              ? l10n.settingsPageSignOutBodyNoRecovery
              : l10n.settingsPageSignOutBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          if (noRecovery)
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_LogOutChoice.setUpRecovery),
              child: Text(l10n.securitySetUpRecovery),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_LogOutChoice.logOut),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(
              noRecovery
                  ? l10n.settingsPageSignOutAnyway
                  : l10n.settingsSignOut,
            ),
          ),
        ],
      ),
    );

    switch (choice) {
      case null:
        return;
      case _LogOutChoice.setUpRecovery:
        await navigator.push(
          MaterialPageRoute(builder: (_) => const SecureBackupPage()),
        );
      case _LogOutChoice.logOut:
        if (context.mounted) await signOutThisDeviceOrExplain(context, ref);
    }
  }
}

enum _LogOutChoice { setUpRecovery, logOut }

class _CategoryTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget page;

  const _CategoryTile({
    required this.icon,
    required this.title,
    required this.page,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleIcon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right_outlined),
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
    );
  }
}

class _ProfileRow extends StatefulWidget {
  final Client client;

  const _ProfileRow({required this.client});

  @override
  State<_ProfileRow> createState() => _ProfileRowState();
}

class _ProfileRowState extends State<_ProfileRow> {
  StreamSubscription<void>? _memberSub;
  OwnProfile? _stored;

  @override
  void initState() {
    super.initState();
    final client = widget.client;
    _memberSub = client.onRoomState.stream.listen((update) {
      final state = update.state;
      if (state.type == EventTypes.RoomMember &&
          state.stateKey == client.userID &&
          mounted) {
        setState(() {});
      }
    });
    if (roomWithOwnMember(client) == null) {
      unawaited(
        ownProfileFromStore(client).then((profile) {
          if (profile != null && mounted) setState(() => _stored = profile);
        }),
      );
    }
  }

  @override
  void dispose() {
    _memberSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = widget.client;
    final stored = _stored;
    final profile = stored != null && roomWithOwnMember(client) == null
        ? stored
        : ownProfileFromMemory(client);
    final userId = client.userID ?? '';
    return InkWell(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AccountSettingsPage())),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            MxcAvatar(
              client: client,
              avatarUrl: profile.avatar,
              fallbackText: profile.name,
              toneSeed: userId,
              radius: 28,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge,
                  ),
                  Text(
                    context.l10n.settingsPageProfileSubtitle(
                      userId.localpart ?? userId,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_outlined,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
