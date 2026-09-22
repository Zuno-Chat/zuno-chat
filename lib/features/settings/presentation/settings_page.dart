import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/errors/feedback.dart';
import '../../../core/location/map_tile_cache.dart';
import '../../../core/matrix/gateway_credentials.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/own_profile.dart';
import '../../../core/notifications/notification_delivery_provider.dart';
import '../../../core/security/account_security_status.dart';
import '../../../core/security/new_device_alert_provider.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import '../../../core/ui/circle_icon.dart';
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
  final bool showFeedback;

  const SettingsPage({this.showFeedback = feedbackAvailable, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final client = ref.watch(matrixClientProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: CardListView(
        children: [
          CardGroup(children: [_ProfileRow(client: client)]),
          const CardGroup(
            children: [
              _CategoryTile(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                subtitle: 'Sounds, delivery',
                page: NotificationsSettingsPage(),
              ),
              _CategoryTile(
                icon: Icons.chat_bubble_outline,
                title: 'Chats & calls',
                subtitle: 'Theme, typing, calls',
                page: ChatsCallsSettingsPage(),
              ),
              _CategoryTile(
                icon: Icons.data_usage_outlined,
                title: 'Data & storage',
                subtitle: 'Media size, call data, cache',
                page: DataStorageSettingsPage(),
              ),
            ],
          ),
          CardGroup(
            children: [
              const _CategoryTile(
                icon: Icons.shield_outlined,
                title: 'Security',
                subtitle: 'Recovery, devices, screenshots',
                page: SecurityPrivacySettingsPage(),
              ),
              const _CategoryTile(
                icon: Icons.info_outline,
                title: 'About',
                subtitle: 'Version, donate, diagnostics',
                page: AboutPage(),
              ),
              if (showFeedback)
                ListTile(
                  leading: const CircleIcon(Icons.feedback_outlined),
                  title: const Text('Send feedback'),
                  onTap: () => showFeedbackSheet(context),
                ),
            ],
          ),
          CardGroup(
            children: [
              ListTile(
                leading: const CircleIcon(Icons.logout_outlined, danger: true),
                title: Text('Sign out', style: TextStyle(color: colors.error)),
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

    final choice = await showDialog<_LogOutChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        actionsOverflowDirection: VerticalDirection.up,
        actionsOverflowButtonSpacing: 4,
        content: Text(
          noRecovery
              ? 'Messages on this device are gone for good. Without a recovery '
                    'code, nobody can restore them.'
              : 'You will need your password to sign back in. Your recovery '
                    'code brings your messages back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          if (noRecovery)
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_LogOutChoice.setUpRecovery),
              child: const Text('Set up recovery'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_LogOutChoice.logOut),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(noRecovery ? 'Sign out anyway' : 'Sign out'),
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
        await _logOut(ref, ref.read(matrixClientProvider));
    }
  }

  Future<void> _logOut(WidgetRef ref, Client client) async {
    await stopAllNotificationDelivery(client);
    final userId = client.userID;
    if (userId != null) {
      await ref.read(knownDevicesStoreProvider).forget(userId);
    }
    await runBestEffort(
      () => GatewayCredentials(client: client).revoke(),
      label: 'revoke gateway token on logout',
    );
    await purgeMapTileCache();
    await client.logout();
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
                    '${withoutServer(userId).replaceFirst('@', '')} · Profile, password',
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
