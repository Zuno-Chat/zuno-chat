import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/cloudflare/calls_gateway_credentials.dart';
import '../../../core/errors/best_effort.dart';
import '../../../core/location/map_tile_cache.dart';
import '../../../core/matrix/device_keys_refresh.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/notifications/notification_delivery_provider.dart';
import '../../../core/security/security_emphasis.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import '../../verification/presentation/approve_this_device_page.dart';
import '../../verification/presentation/verification_page.dart';
import 'session_info.dart';
import 'uia_password_prompt.dart';

class ActiveSessionsPage extends ConsumerStatefulWidget {
  const ActiveSessionsPage({super.key});

  @override
  ConsumerState<ActiveSessionsPage> createState() => _ActiveSessionsPageState();
}

class _ActiveSessionsPageState extends ConsumerState<ActiveSessionsPage> {
  bool _loading = true;
  List<DeviceSessionInfo> _sessions = [];
  StreamSubscription<UiaRequest>? _uiaSub;
  bool _ipRevealed = false;

  @override
  void initState() {
    super.initState();
    final client = ref.read(matrixClientProvider);
    _uiaSub = client.onUiaRequest.stream.listen(_handleUia);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _uiaSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final client = ref.read(matrixClientProvider);
    setState(() => _loading = true);
    try {
      final devicesFuture = client.getDevices();
      markOwnDeviceKeysOutdated(client);
      await client.updateUserDeviceKeys();
      final devices = await devicesFuture;
      final deviceKeys =
          client.userDeviceKeys[client.userID]?.deviceKeys.values.toList() ??
          [];
      final sessions = mergeSessionInfo(
        deviceKeys: [
          for (final d in deviceKeys)
            (
              deviceId: d.deviceId ?? '',
              displayName: d.deviceDisplayName,
              verified: d.verified,
            ),
        ],
        devices: [
          for (final d in devices ?? <Device>[])
            (
              deviceId: d.deviceId,
              displayName: d.displayName,
              lastSeenTs: d.lastSeenTs,
              lastSeenIp: d.lastSeenIp,
            ),
        ],
        currentDeviceId: client.deviceID,
      );
      if (!mounted) return;
      setState(() => _sessions = sessions);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleUia(UiaRequest uia) async {
    if (uia.state != UiaRequestState.waitForUser) return;
    final client = ref.read(matrixClientProvider);
    final password = await askPasswordForUia(context);
    if (!mounted) return;
    if (password == null || password.isEmpty) {
      uia.cancel();
      return;
    }
    await uia.completeStage(
      AuthenticationPassword(
        session: uia.session,
        password: password,
        identifier: AuthenticationUserIdentifier(user: client.userID!),
      ),
    );
  }

  Future<void> _signOut(
    Future<void> Function(AuthenticationData? auth) request,
  ) async {
    final client = ref.read(matrixClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await client.uiaRequestBackground<void>(request);
    } catch (e) {
      if (e.toString().contains('canceled')) return;
      logCaught('sign out other devices', e);
      messenger.showSnackBar(
        const SnackBar(content: Text('Not signed out. Try again.')),
      );
      return;
    }
    if (mounted) await _refresh();
  }

  Future<void> _signOutCurrentSession() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final client = ref.read(matrixClientProvider);
      await stopAllNotificationDelivery(client);
      await runBestEffort(
        () => CallsGatewayCredentials(client: client).revoke(),
        label: 'revoke calls gateway token on logout',
      );
      await purgeMapTileCache();
      await client.logout();
    } catch (e) {
      logCaught('sign out', e);
      messenger.showSnackBar(
        const SnackBar(content: Text('Not signed out. Try again.')),
      );
    }
  }

  Future<void> _approveThisDevice() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ApproveThisDevicePage()));
    if (mounted) await _refresh();
  }

  Future<void> _confirmAndSignOutOthers() async {
    final otherIds = _sessions
        .where((s) => !s.isCurrent)
        .map((s) => s.deviceId)
        .toList();
    if (otherIds.isEmpty) return;
    final confirmed = await _confirmSignOut(
      title:
          'Sign out of ${otherIds.length} other device${otherIds.length == 1 ? '' : 's'}?',
      body:
          'Every other device on this account will need to sign in again. This '
          'device is not affected.',
    );
    if (confirmed != true || !mounted) return;
    await _signOut(
      (auth) =>
          ref.read(matrixClientProvider).deleteDevices(otherIds, auth: auth),
    );
  }

  Future<void> _confirmAndSignOutOne(DeviceSessionInfo session) async {
    final confirmed = await _confirmSignOut(
      title: 'Sign out of "${session.displayName ?? session.deviceId}"?',
      body: 'That device will need to sign in again.',
    );
    if (confirmed != true || !mounted) return;
    await _signOut(
      (auth) => ref
          .read(matrixClientProvider)
          .deleteDevice(session.deviceId, auth: auth),
    );
  }

  Future<bool?> _confirmSignOut({required String title, required String body}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  Future<void> _verify(String deviceId) async {
    final client = ref.read(matrixClientProvider);
    final device = client.userDeviceKeys[client.userID]?.deviceKeys[deviceId];
    if (device == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final keyVerification = await device.startVerification();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerificationPage(
            keyVerification: keyVerification,
            isOwnDevice: true,
          ),
        ),
      );
      await _refresh();
    } catch (e) {
      logCaught('start device approval', e);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not start approving that device. Try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _sessions.where((s) => s.isCurrent).firstOrNull;
    final others = _sessions.where((s) => !s.isCurrent).toList();
    final thisDeviceHasIdentityKeys = ref
        .watch(accountSecurityFactsProvider)
        .value
        ?.thisDeviceHasIdentityKeys;

    return Scaffold(
      appBar: AppBar(title: const Text('Your devices')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: CardListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 4, 12, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Signed in',
                            style: cardGroupTitleStyle(context),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => _ipRevealed = !_ipRevealed),
                          child: Text(_ipRevealed ? 'Hide IP' : 'Show IP'),
                        ),
                      ],
                    ),
                  ),
                  if (current != null)
                    CardGroup(
                      children: [
                        _SessionTile(
                          session: current,
                          ipRevealed: _ipRevealed,
                          thisDeviceHasIdentityKeys: thisDeviceHasIdentityKeys,
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Wrap(
                            spacing: 8,
                            children: [
                              if (sessionApproval(
                                    isCurrent: true,
                                    verified: current.verified,
                                    thisDeviceHasIdentityKeys:
                                        thisDeviceHasIdentityKeys,
                                  ) ==
                                  SessionApproval.notApproved)
                                FilledButton(
                                  onPressed: _approveThisDevice,
                                  child: const Text('Approve this device'),
                                ),
                              OutlinedButton(
                                onPressed: _signOutCurrentSession,
                                child: const Text('Sign out this device'),
                              ),
                              if (others.isNotEmpty)
                                OutlinedButton(
                                  onPressed: _confirmAndSignOutOthers,
                                  child: const Text('Sign out everywhere else'),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  if (others.isNotEmpty)
                    CardGroup(
                      children: [
                        for (final session in others)
                          _SessionTile(
                            session: session,
                            ipRevealed: _ipRevealed,
                            thisDeviceHasIdentityKeys:
                                thisDeviceHasIdentityKeys,
                            onVerify: session.verified
                                ? null
                                : () => _verify(session.deviceId),
                            onSignOut: () => _confirmAndSignOutOne(session),
                          ),
                      ],
                    ),
                  if (_sessions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 96),
                      child: Center(child: Text('No devices found.')),
                    ),
                ],
              ),
            ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final DeviceSessionInfo session;
  final bool ipRevealed;
  final bool? thisDeviceHasIdentityKeys;
  final VoidCallback? onVerify;
  final VoidCallback? onSignOut;

  const _SessionTile({
    required this.session,
    required this.ipRevealed,
    required this.thisDeviceHasIdentityKeys,
    this.onVerify,
    this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final approval = sessionApproval(
      isCurrent: session.isCurrent,
      verified: session.verified,
      thisDeviceHasIdentityKeys: thisDeviceHasIdentityKeys,
    );
    final subtitleParts = <String>[
      switch (approval) {
        SessionApproval.unknown =>
          session.isCurrent ? 'Checking…' : 'Cannot check from this device',
        SessionApproval.approved => 'Approved',
        SessionApproval.notApproved => 'Not approved yet',
      },
      session.lastActivity == null
          ? 'Last activity unknown'
          : 'Last active ${formatLastActivity(session.lastActivity)}',
      if (ipRevealed && session.ipAddress != null) session.ipAddress!,
    ];
    final (icon, iconColor) = switch (approval) {
      SessionApproval.unknown => (
        Icons.help_outline,
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      SessionApproval.approved => (
        deviceApprovedIcon,
        deviceApprovedColor(context),
      ),
      SessionApproval.notApproved => (
        deviceUnapprovedIcon,
        deviceUnapprovedColor(context),
      ),
    };
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Row(
        children: [
          Flexible(
            child: Text(
              session.displayName ?? session.deviceId,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (session.isCurrent) ...[
            const SizedBox(width: 8),
            Chip(
              label: const Text('This device'),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              labelStyle: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ],
      ),
      subtitle: Text(subtitleParts.join(' · ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onVerify != null)
            TextButton(onPressed: onVerify, child: const Text('Approve')),
          if (onSignOut != null)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign out of this device',
              onPressed: onSignOut,
            ),
        ],
      ),
    );
  }
}
