import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../errors/best_effort.dart';
import '../../l10n/l10n.dart';
import '../../matrix/matrix_client_provider.dart';
import '../../settings/app_preferences_provider.dart';
import '../account_security_status.dart';
import '../security_providers.dart';
import '../user_trust.dart';
import 'known_devices_store.dart';
import 'known_identity_store.dart';
import 'security_alert.dart';
import 'security_alert_detection.dart';
import 'security_alert_notifications.dart';
import 'security_alert_store.dart';

const _signInDetailsBudget = Duration(seconds: 5);

final knownDevicesStoreProvider = Provider<KnownDevicesStore>((ref) {
  return KnownDevicesStore(ref.watch(sharedPreferencesProvider));
});

final knownIdentityStoreProvider = Provider<KnownIdentityStore>((ref) {
  return KnownIdentityStore(ref.watch(sharedPreferencesProvider));
});

final securityAlertStoreProvider = Provider<SecurityAlertStore>((ref) {
  return SecurityAlertStore(ref.watch(sharedPreferencesProvider));
});

Stream<SyncStatusUpdate> _onSyncFinished(Client client) => client
    .onSyncStatus
    .stream
    .where((update) => update.status == SyncStatus.finished);

final ownIdentityResetHoldProvider =
    NotifierProvider<OwnIdentityResetHold, bool>(OwnIdentityResetHold.new);

class OwnIdentityResetHold extends Notifier<bool> {
  @override
  bool build() => false;

  void hold() => state = true;

  Future<void> release() async {
    if (!state) return;
    final client = ref.read(matrixClientProvider);
    final userId = client.userID;
    final identityKey = client.userDeviceKeys[userId]?.masterKey?.ed25519Key;
    final remembered = userId == null || identityKey == null
        ? null
        : ref.read(knownIdentityStoreProvider).remember(userId, identityKey);
    state = false;
    await remembered;
  }
}

final dismissedSecurityStatusProvider =
    NotifierProvider<DismissedSecurityStatus, AccountSecurityStatus?>(
      DismissedSecurityStatus.new,
    );

class DismissedSecurityStatus extends Notifier<AccountSecurityStatus?> {
  @override
  AccountSecurityStatus? build() {
    ref.watch(isLoggedInProvider);
    return null;
  }

  void dismiss(AccountSecurityStatus status) => state = status;
}

final securityAlertsProvider =
    NotifierProvider<SecurityAlertsNotifier, List<RecordedSecurityAlert>>(
      SecurityAlertsNotifier.new,
    );

final accountSecurityAlertsProvider = Provider<List<SecurityAlert>>(
  (ref) => accountSecurityAlerts(
    recorded: ref.watch(securityAlertsProvider),
    status: ref.watch(accountSecurityStatusProvider).value,
    dismissedStatus: ref.watch(dismissedSecurityStatusProvider),
  ),
);

final unvouchedCallDeviceProvider =
    Provider.family<bool, ({String userId, String deviceId})>((ref, device) {
      ref.watch(accountSecurityFactsProvider);
      return callDeviceUnvouched(
        ref.watch(matrixClientProvider),
        device,
        recorded: ref.watch(securityAlertsProvider),
      );
    });

class SecurityAlertsNotifier extends Notifier<List<RecordedSecurityAlert>> {
  bool _busy = false;

  @override
  List<RecordedSecurityAlert> build() {
    ref.watch(isLoggedInProvider);
    final client = ref.watch(matrixClientProvider);
    final sub = _onSyncFinished(client)
        .listen((_) => unawaited(_check(client)));
    ref.onDispose(sub.cancel);
    unawaited(_check(client));
    final userId = client.userID;
    return userId == null
        ? const []
        : ref.read(securityAlertStoreProvider).open(userId);
  }

  Future<void> dismiss(RecordedSecurityAlert alert) async {
    final userId = ref.read(matrixClientProvider).userID;
    if (userId == null) return;
    state = [
      for (final open in state)
        if (open.key != alert.key) open,
    ];
    await ref.read(securityAlertStoreProvider).save(userId, state);
  }

  Future<void> _check(Client client) async {
    if (_busy) return;
    final userId = client.userID;
    if (userId == null) return;

    _busy = true;
    try {
      final knownDevices = ref.read(knownDevicesStoreProvider);
      final resets = await _recoveryResets(client, userId);
      final signIns = await _newSignIns(client, userId, knownDevices);
      final unvouched = await _unvouchedDevices(client, knownDevices);
      if (!ref.mounted) return;

      final open = withRaised(state, [
        ...resets,
        ...signIns,
        ...unvouched,
      ]).where((alert) => securityAlertStillOpen(alert, client)).toList();
      if (!listEquals(open, state)) {
        state = open;
        await ref.read(securityAlertStoreProvider).save(userId, open);
      }

      for (final alert in [...resets, ...signIns]) {
        if (open.contains(alert)) await _notify(alert);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _notify(RecordedSecurityAlert alert) async {
    final l10n = deviceLocalizations();
    final text = switch (alert) {
      RecoveryResetAlert() => recoveryResetText(l10n),
      NewSignInAlert() => newSignInText(l10n, alert),
      UnvouchedDeviceAlert() => null,
    };
    if (text == null) return;
    await runBestEffort(
      () => SecurityAlertNotifications.instance.show(
        alertKey: alert.key,
        title: text.title,
        body: text.body,
      ),
      label: 'show a security alert notification',
    );
  }

  Future<List<RecoveryResetAlert>> _recoveryResets(
    Client client,
    String userId,
  ) async {
    if (ref.read(ownIdentityResetHoldProvider)) return const [];
    final keys = readyDeviceKeys(client, userId);
    final current = keys?.masterKey?.ed25519Key;
    if (keys == null || current == null) return const [];
    final knownIdentity = ref.read(knownIdentityStoreProvider);
    final alerts = recoveryResetAlerts(
      knownIdentityKey: knownIdentity.identityKey(userId),
      currentIdentityKey: current,
      thisDeviceApproved: deviceApprovedByOwner(
        keys.deviceKeys[client.deviceID],
      ),
    );
    await knownIdentity.remember(userId, current);
    return alerts;
  }

  Future<List<NewSignInAlert>> _newSignIns(
    Client client,
    String userId,
    KnownDevicesStore knownDevices,
  ) async {
    final keys = readyDeviceKeys(client, userId);
    if (keys == null) return const [];
    final current = {
      for (final entry in keys.deviceKeys.entries)
        entry.key: entry.value.deviceDisplayName,
    };
    final alerts = newSignInAlerts(
      knownDeviceIds: knownDevices.knownDeviceIds(userId),
      currentDevices: current,
      ownDeviceId: client.deviceID,
    );
    await knownDevices.remember(userId, current.keys.toSet());
    return [for (final alert in alerts) await _withDetails(client, alert)];
  }

  Future<NewSignInAlert> _withDetails(
    Client client,
    NewSignInAlert alert,
  ) async {
    Device? device;
    await runBestEffort(
      () async => device = await client
          .getDevice(alert.deviceId)
          .timeout(_signInDetailsBudget),
      label: 'read a new sign-in',
    );
    final seenMs = device?.lastSeenTs;
    return NewSignInAlert(
      deviceId: alert.deviceId,
      displayName: alert.displayName,
      ipAddress: device?.lastSeenIp,
      seenAt: seenMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(seenMs),
    );
  }

  Future<List<UnvouchedDeviceAlert>> _unvouchedDevices(
    Client client,
    KnownDevicesStore knownDevices,
  ) async {
    final alerts = <UnvouchedDeviceAlert>[];
    for (final userId in peopleWhoseDevicesWeWatch(client)) {
      final keys = readyDeviceKeys(client, userId);
      if (keys == null) continue;
      final current = keys.deviceKeys.keys.toSet();
      final unvouched = unvouchedNewDeviceIds(
        hasIdentity: keys.masterKey != null,
        knownDeviceIds: knownDevices.knownDeviceIds(userId),
        currentDeviceIds: current,
      );
      await knownDevices.remember(userId, current);
      if (unvouched.isNotEmpty) {
        alerts.add(UnvouchedDeviceAlert(userId: userId, deviceIds: unvouched));
      }
    }
    return alerts;
  }
}
