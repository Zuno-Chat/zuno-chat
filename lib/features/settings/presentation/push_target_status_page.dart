import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/notifications/fcm_delivery_provider.dart';
import '../../../core/notifications/notification_delivery_mode.dart';
import '../../../core/notifications/notification_delivery_provider.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/push/matrix_unified_push_gateway.dart';
import '../../../core/push/pusher_info.dart';
import '../../../core/push/pusher_reconciliation.dart';
import '../../../core/push/unified_push_distributor_names.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import 'voip_dev_export_card.dart';

class PushTargetStatusPage extends ConsumerStatefulWidget {
  const PushTargetStatusPage({super.key});

  @override
  ConsumerState<PushTargetStatusPage> createState() =>
      _PushTargetStatusPageState();
}

class _PushTargetStatusPageState extends ConsumerState<PushTargetStatusPage> {
  String? _distributor;

  List<PusherInfo>? _pushers;

  bool _pushersFailed = false;

  bool _removing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  NotificationDeliveryMode get _mode =>
      ref.read(notificationDeliveryModeProvider);

  Future<void> _refresh() async {
    final mode = _mode;
    final client = ref.read(matrixClientProvider);
    final distributor = mode == NotificationDeliveryMode.unifiedPush
        ? await unifiedPushDeliveryProvider.knownDistributor()
        : null;
    final pushers = await fetchPushers(client);
    if (!mounted) return;
    setState(() {
      _distributor = distributor ?? '';
      _pushers = pushers ?? const [];
      _pushersFailed = pushers == null;
    });
  }

  void _showNotRemoved() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Not removed. Try again.')));
  }

  Future<void> _removeTarget() async {
    final mode = _mode;
    final confirmed = await _confirm(
      title: 'Remove push target?',
      message:
          'This device stops receiving notifications until you register again '
          'or Zuno restarts. ${_removalDetail(mode)}',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removing = true);
    final client = ref.read(matrixClientProvider);
    var failed = false;
    try {
      if (mode == NotificationDeliveryMode.unifiedPush) {
        await unifiedPushDeliveryProvider.remove(client);
      } else {
        await fcmDeliveryProvider.remove(client);
      }
    } catch (e) {
      logCaught('remove push target', e);
      failed = true;
    }
    if (!mounted) return;
    setState(() => _removing = false);
    if (failed) {
      _showNotRemoved();
    } else {
      Navigator.of(context).pop();
    }
  }

  String _removalDetail(NotificationDeliveryMode mode) {
    return mode == NotificationDeliveryMode.unifiedPush
        ? 'The server forgets this device, and the distributor '
              'registration is dropped.'
        : "The server forgets this device, and this device's registration "
              'token is dropped.';
  }

  Future<void> _removeOtherPusher(PusherInfo pusher) async {
    final name = _pusherName(pusher);
    final confirmed = await _confirm(
      title: 'Remove this push target?',
      message:
          '"$name" stops receiving push notifications for this account '
          'until whichever app or device owns it registers again.',
    );
    if (confirmed != true) return;
    await _deletePushers([pusher]);
  }

  Future<void> _removeAllOtherPushers(List<PusherInfo> pushers) async {
    final confirmed = await _confirm(
      title: pushers.length == 1
          ? 'Remove this push target?'
          : 'Remove ${pushers.length} push targets?',
      message:
          'Every other device and app registered for notifications on this '
          'account stops receiving them until it registers again. This '
          "device's own target is left alone.",
    );
    if (confirmed != true) return;
    await _deletePushers(pushers);
  }

  Future<void> _deletePushers(List<PusherInfo> pushers) async {
    if (!mounted) return;
    setState(() => _removing = true);
    final client = ref.read(matrixClientProvider);
    var failed = false;
    for (final pusher in pushers) {
      try {
        await client.deletePusher(
          PusherId(appId: pusher.appId, pushkey: pusher.pushkey),
        );
      } catch (e) {
        logCaught('remove other push target', e);
        failed = true;
      }
    }
    if (!mounted) return;
    setState(() => _removing = false);
    if (failed) _showNotRemoved();
    await _refresh();
  }

  Future<bool?> _confirm({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final capabilities = ref.watch(platformCapabilitiesProvider);
    final mode = ref.watch(notificationDeliveryModeProvider);
    final client = ref.watch(matrixClientProvider);
    final currentPushkey = currentPushkeyFor(mode);
    final gatewayUrl = gatewayUrlFor(mode, client);
    final lastPusherError = lastPusherErrorFor(mode);
    final distributor = _distributor;
    final pushers = _pushers;
    final groups = groupPushers(pushers ?? const [], currentPushkey);
    final current = groups.currentSession;

    return Scaffold(
      appBar: AppBar(title: const Text('Push target')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CardListView(
          children: [
            CardGroup(
              title: 'This device',
              children: [
                if (mode == NotificationDeliveryMode.unifiedPush)
                  _DetailRow(
                    label: 'Distributor',
                    value: switch (distributor) {
                      null => null,
                      '' => 'None',
                      final name => unifiedPushDistributorDisplayName(name),
                    },
                  ),
                _DetailRow(label: 'App ID', value: current?.appId),
                _DetailRow(
                  label: 'Push key',
                  value: current?.pushkey ?? currentPushkey,
                ),
                _DetailRow(
                  label: 'App display name',
                  value: current?.appDisplayName,
                ),
                _DetailRow(
                  label: 'Device name',
                  value: current?.deviceDisplayName,
                ),
                _DetailRow(
                  label: 'Device ID',
                  value: current?.deviceId ?? client.deviceID,
                ),
                _DetailRow(
                  label: 'Push gateway URL',
                  value: current?.url ?? gatewayUrl?.toString(),
                ),
                _DetailRow(label: 'Format', value: current?.format),
                if (_usesPublicGateway(current?.url ?? gatewayUrl?.toString()))
                  ListTile(
                    leading: Icon(Icons.info_outline, color: colors.tertiary),
                    title: const Text('Using the public push bridge'),
                    subtitle: const Text(
                      'Your push server has no gateway of its own, so '
                      'notifications go through a community-run one. It sees '
                      'that a message arrived and when. It never sees who sent '
                      'it or what it said. Use a push server with a built-in '
                      'gateway, or host your own, to avoid this.',
                    ),
                  ),
                if (lastPusherError != null)
                  ListTile(
                    leading: Icon(Icons.error_outline, color: colors.error),
                    title: const Text('Last error'),
                    subtitle: Text(lastPusherError),
                  ),
                if (mode == NotificationDeliveryMode.fcm ||
                    mode == NotificationDeliveryMode.unifiedPush)
                  ListTile(
                    leading: _removing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: Padding(
                              padding: EdgeInsets.all(2),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Icon(Icons.delete_outline, color: colors.error),
                    title: Text(
                      'Remove push target',
                      style: TextStyle(color: colors.error),
                    ),
                    subtitle: Text(_removalSubtitle(mode)),
                    onTap: _removing ? null : _removeTarget,
                  ),
              ],
            ),
            CardGroup(
              children: [
                _SectionHeaderWithAction(
                  title: 'Other push registrations',
                  onRemoveAll: groups.others.isEmpty || _removing
                      ? null
                      : () => _removeAllOtherPushers(groups.others),
                ),
                ..._pusherRows(groups.others, pushers == null),
              ],
            ),
            if (capabilities.voipRing) const VoipDevExportCard(),
          ],
        ),
      ),
    );
  }

  String _removalSubtitle(NotificationDeliveryMode mode) {
    return mode == NotificationDeliveryMode.unifiedPush
        ? 'Makes the server forget this device and unregisters from the '
              'distributor'
        : "Makes the server forget this device and drops this device's "
              'registration token';
  }

  List<Widget> _pusherRows(List<PusherInfo> pushers, bool loading) {
    if (loading) return const [_EmptyNote('Loading…')];
    if (_pushersFailed) {
      return const [_EmptyNote('Could not load. Pull down to try again.')];
    }
    if (pushers.isEmpty) return const [_EmptyNote('None')];
    return [
      for (final pusher in pushers)
        ListTile(
          leading: const Icon(Icons.devices_other_outlined),
          title: Text(_pusherName(pusher)),
          subtitle: Text('${pusher.appId}\n${pusher.url ?? pusher.pushkey}'),
          isThreeLine: true,
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove',
            onPressed: _removing ? null : () => _removeOtherPusher(pusher),
          ),
        ),
    ];
  }
}

class _SectionHeaderWithAction extends StatelessWidget {
  final String title;
  final VoidCallback? onRemoveAll;
  const _SectionHeaderWithAction({required this.title, this.onRemoveAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          children: [
            Expanded(child: Text(title, style: cardGroupTitleStyle(context))),
            if (onRemoveAll != null)
              TextButton(
                onPressed: onRemoveAll,
                child: const Text('Remove all'),
              ),
          ],
        ),
      ),
    );
  }
}

String _pusherName(PusherInfo pusher) {
  if (pusher.deviceDisplayName.isNotEmpty) return pusher.deviceDisplayName;
  if (pusher.appDisplayName.isNotEmpty) return pusher.appDisplayName;
  return pusher.appId;
}

bool _usesPublicGateway(String? url) {
  if (url == null) return false;
  return Uri.tryParse(url)?.host == fallbackMatrixGatewayUrl.host;
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String? value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = value ?? '';
    return ListTile(
      dense: true,
      title: Text(label, style: theme.textTheme.labelMedium),
      subtitle: SelectableText(
        shown.isEmpty ? '—' : shown,
        style: TextStyle(
          color: shown.isEmpty
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final String text;
  const _EmptyNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
