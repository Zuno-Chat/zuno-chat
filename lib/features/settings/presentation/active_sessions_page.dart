import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/format/date_labels.dart';
import '../../../core/format/human_units.dart';
import '../../../core/l10n/display_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/device_keys_refresh.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/sign_out.dart';
import '../../../core/matrix/uia_cancel.dart';
import '../../../core/security/security_emphasis.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import '../../../core/ui/confirm_dialog.dart';
import '../../../core/ui/notice.dart';
import '../../verification/presentation/approve_this_device_page.dart';
import '../../verification/presentation/start_verification.dart';
import 'session_info.dart';
import 'sign_in_another_device_page.dart';
import 'uia_password_prompt.dart';

class ActiveSessionsPage extends ConsumerStatefulWidget {
  const ActiveSessionsPage({super.key});

  @override
  ConsumerState<ActiveSessionsPage> createState() => _ActiveSessionsPageState();
}

class _ActiveSessionsPageState extends ConsumerState<ActiveSessionsPage> {
  bool _loading = true;
  bool _loadFailed = false;
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
    try {
      markOwnDeviceKeysOutdated(client);
      final (devices, _) = await (
        client.getDevices(),
        client.updateUserDeviceKeys(),
      ).wait;
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
      setState(() {
        _sessions = sessions;
        _loadFailed = false;
      });
    } catch (e, s) {
      reportCaught('load devices', e, s);
      if (!mounted) return;
      if (_sessions.isEmpty) {
        setState(() => _loadFailed = true);
      } else {
        ScaffoldMessenger.of(context).sayFailed(
          context.l10n,
          e,
          failed: context.l10n.settingsSessionsRefreshFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleUia(UiaRequest uia) => answerUiaWithPassword(
    context,
    uia,
    userId: ref.read(matrixClientProvider).userID!,
  );

  Future<void> _signOut(
    Future<void> Function(AuthenticationData? auth) request,
  ) async {
    final client = ref.read(matrixClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await client.uiaRequestBackground<void>(request);
    } catch (e, s) {
      if (isUiaCancel(e)) return;
      reportCaught('sign out other devices', e, s);
      messenger.sayFailed(l10n, e, failed: l10n.settingsSessionsSignOutFailed);
      return;
    }
    if (mounted) await _refresh();
  }

  Future<void> _signOutCurrentSession() async {
    final confirmed = await _confirmSignOut(
      title: context.l10n.settingsSessionsSignOutThisTitle,
      body: context.l10n.settingsSessionsSignOutThisBody,
    );
    if (!confirmed || !mounted) return;
    await signOutThisDeviceOrExplain(context, ref);
  }

  Future<void> _showSignInCode() async {
    final client = ref.read(matrixClientProvider);
    _uiaSub?.cancel();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SignInAnotherDevicePage()));
    if (!mounted) return;
    _uiaSub = client.onUiaRequest.stream.listen(_handleUia);
    await _refresh();
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
      title: context.l10n.settingsSessionsSignOutOthersTitle(otherIds.length),
      body: context.l10n.settingsSessionsSignOutOthersBody,
    );
    if (!confirmed || !mounted) return;
    await _signOut(
      (auth) =>
          ref.read(matrixClientProvider).deleteDevices(otherIds, auth: auth),
    );
  }

  Future<void> _confirmAndSignOutOne(DeviceSessionInfo session) async {
    final confirmed = await _confirmSignOut(
      title: context.l10n.settingsSessionsSignOutOneTitle(
        session.displayName ?? session.deviceId,
      ),
      body: context.l10n.settingsSessionsSignOutOneBody,
    );
    if (!confirmed || !mounted) return;
    await _signOut(
      (auth) => ref
          .read(matrixClientProvider)
          .deleteDevice(session.deviceId, auth: auth),
    );
  }

  Future<bool> _confirmSignOut({
    @displayText required String title,
    @displayText required String body,
  }) => confirm(
    context,
    title: title,
    body: body,
    confirmLabel: context.l10n.settingsSignOut,
    tone: ConfirmTone.destructive,
  );

  Future<void> _verify(String deviceId) async {
    final client = ref.read(matrixClientProvider);
    final device = client.userDeviceKeys[client.userID]?.deviceKeys[deviceId];
    if (device == null) return;
    final verification = await startAndOpenVerification(
      context,
      device.startVerification,
      label: 'start device approval',
      failed: context.l10n.settingsSessionsApproveFailed,
      isOwnDevice: true,
    );
    if (verification != null && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final current = _sessions.where((s) => s.isCurrent).firstOrNull;
    final others = _sessions.where((s) => !s.isCurrent).toList();
    final thisDeviceHasIdentityKeys = ref
        .watch(accountSecurityFactsProvider)
        .value
        ?.thisDeviceHasIdentityKeys;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsSessionsTitle)),
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
                            l10n.settingsSessionsSignedIn,
                            style: cardGroupTitleStyle(context),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => _ipRevealed = !_ipRevealed),
                          child: Text(
                            _ipRevealed
                                ? l10n.settingsSessionsHideIp
                                : l10n.settingsSessionsShowIp,
                          ),
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
                                  child: Text(
                                    l10n.settingsSessionsApproveThisDevice,
                                  ),
                                ),
                              OutlinedButton(
                                onPressed: _signOutCurrentSession,
                                child: Text(
                                  l10n.settingsSessionsSignOutThisDevice,
                                ),
                              ),
                              if (others.isNotEmpty)
                                OutlinedButton(
                                  onPressed: _confirmAndSignOutOthers,
                                  child: Text(
                                    l10n.settingsSessionsSignOutEverywhereElse,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  CardGroup(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.qr_code_2_outlined),
                        title: Text(l10n.settingsSessionsSignInOnAnother),
                        subtitle: Text(
                          l10n.settingsSessionsSignInOnAnotherSubtitle,
                        ),
                        trailing: const Icon(Icons.chevron_right_outlined),
                        onTap: _showSignInCode,
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
                    Padding(
                      padding: const EdgeInsets.only(top: 96),
                      child: Center(
                        child: Text(
                          _loadFailed
                              ? l10n.settingsSessionsLoadFailed
                              : l10n.settingsSessionsNone,
                        ),
                      ),
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
    final l10n = context.l10n;
    final subtitleParts = <String>[
      switch (approval) {
        SessionApproval.unknown =>
          session.isCurrent
              ? l10n.commonChecking
              : l10n.settingsSessionsCannotCheck,
        SessionApproval.approved => l10n.settingsSessionsApproved,
        SessionApproval.notApproved => l10n.settingsSessionsNotApproved,
      },
      if (session.lastActivity case final lastActivity?)
        l10n.settingsSessionsLastActive(
          DateLabels.of(context).dateTime(lastActivity),
        )
      else
        l10n.settingsSessionsLastActivityUnknown,
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
              label: Text(l10n.settingsSessionsThisDevice),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              labelStyle: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ],
      ),
      subtitle: Text(joinDetails(subtitleParts)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onVerify != null)
            TextButton(
              onPressed: onVerify,
              child: Text(l10n.settingsSessionsApprove),
            ),
          if (onSignOut != null)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: l10n.settingsSessionsSignOutThisTooltip,
              onPressed: onSignOut,
            ),
        ],
      ),
    );
  }
}
