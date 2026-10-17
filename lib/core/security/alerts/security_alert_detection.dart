import 'package:matrix/matrix.dart';

import '../../l10n/l10n.dart';
import '../../matrix/room_access.dart';
import '../account_security_status.dart';
import '../user_trust.dart';
import 'security_alert.dart';

List<NewSignInAlert> newSignInAlerts({
  required Set<String>? knownDeviceIds,
  required Map<String, String?> currentDevices,
  required String? ownDeviceId,
}) {
  if (knownDeviceIds == null) return const [];
  return [
    for (final entry in currentDevices.entries)
      if (entry.key != ownDeviceId && !knownDeviceIds.contains(entry.key))
        NewSignInAlert(deviceId: entry.key, displayName: entry.value),
  ];
}

Set<String> unvouchedNewDeviceIds({
  required bool hasIdentity,
  required Set<String>? knownDeviceIds,
  required Set<String> currentDeviceIds,
}) {
  if (hasIdentity || knownDeviceIds == null) return const {};
  return currentDeviceIds.difference(knownDeviceIds);
}

Set<String> peopleWhoseDevicesWeWatch(Client client) {
  final ownId = client.userID;
  return {
    for (final room in client.rooms)
      if (room.membership == Membership.join &&
          !room.isSpace &&
          roomAccessOf(room) != RoomAccess.public)
        for (final user in room.getParticipants([Membership.join]))
          if (user.id != ownId) user.id,
  };
}

List<RecoveryResetAlert> recoveryResetAlerts({
  required String? knownIdentityKey,
  required String? currentIdentityKey,
  required bool thisDeviceApproved,
}) {
  if (knownIdentityKey == null || currentIdentityKey == null) return const [];
  if (knownIdentityKey == currentIdentityKey || thisDeviceApproved) {
    return const [];
  }
  return [RecoveryResetAlert(currentIdentityKey)];
}

DeviceKeysList? readyDeviceKeys(Client client, String? userId) {
  final keys = client.userDeviceKeys[userId];
  if (keys == null || keys.outdated || keys.deviceKeys.isEmpty) return null;
  return keys;
}

List<RecordedSecurityAlert> withRaised(
  List<RecordedSecurityAlert> open,
  List<RecordedSecurityAlert> raised,
) {
  final merged = {for (final alert in open) alert.key: alert};
  for (final alert in raised) {
    merged[alert.key] = switch ((merged[alert.key], alert)) {
      (
        UnvouchedDeviceAlert(deviceIds: final before),
        UnvouchedDeviceAlert(:final userId, :final deviceIds),
      ) =>
        UnvouchedDeviceAlert(
          userId: userId,
          deviceIds: {...before, ...deviceIds},
        ),
      _ => alert,
    };
  }
  return merged.values.toList();
}

bool securityAlertStillOpen(RecordedSecurityAlert alert, Client client) {
  switch (alert) {
    case RecoveryResetAlert(:final identityKey):
      final keys = readyDeviceKeys(client, client.userID);
      if (keys == null) return true;
      return keys.masterKey?.ed25519Key == identityKey &&
          !deviceApprovedByOwner(keys.deviceKeys[client.deviceID]);
    case NewSignInAlert(:final deviceId):
      final keys = readyDeviceKeys(client, client.userID);
      if (keys == null) return true;
      final device = keys.deviceKeys[deviceId];
      return device != null && !device.verified;
    case UnvouchedDeviceAlert(:final userId, :final deviceIds):
      final keys = readyDeviceKeys(client, userId);
      if (keys == null) return true;
      return keys.masterKey == null &&
          deviceIds.any(keys.deviceKeys.containsKey);
  }
}

List<SecurityAlert> accountSecurityAlerts({
  required List<RecordedSecurityAlert> recorded,
  required AccountSecurityStatus? status,
  required AccountSecurityStatus? dismissedStatus,
}) {
  final resets = recorded.whereType<RecoveryResetAlert>().toList();
  final signIns = recorded.whereType<NewSignInAlert>().toList();
  final statusShown = switch (status) {
    AccountSecurityStatus.deviceLocked => resets.isEmpty,
    AccountSecurityStatus.deviceWaiting => signIns.isEmpty,
    AccountSecurityStatus.recoveryStale => true,
    AccountSecurityStatus.noRecovery ||
    AccountSecurityStatus.protected ||
    null => false,
  };
  return [
    ...resets,
    ...signIns,
    if (statusShown && status != dismissedStatus) AccountStatusAlert(status!),
  ];
}

bool callDeviceUnvouched(
  Client client,
  ({String userId, String deviceId}) device, {
  required List<RecordedSecurityAlert> recorded,
}) {
  if (device.userId == client.userID) return false;
  final keys = client.userDeviceKeys[device.userId];
  final deviceKeys = keys?.deviceKeys[device.deviceId];
  if (keys == null || deviceKeys == null) return false;
  if (keys.masterKey != null) return !deviceApprovedByOwner(deviceKeys);
  return recorded.whereType<UnvouchedDeviceAlert>().any(
    (alert) =>
        alert.userId == device.userId &&
        alert.deviceIds.contains(device.deviceId),
  );
}

List<SecurityAlert> roomSecurityAlerts(
  Room room, {
  required List<RecordedSecurityAlert> recorded,
  required UserTrustState Function(String userId) trustOf,
}) {
  final ownId = room.client.userID;
  final joined = {
    for (final user in room.getParticipants([Membership.join])) user.id,
  };
  return [
    for (final user in room.getParticipants([
      Membership.join,
      Membership.invite,
    ]))
      if (user.id != ownId && userTrustNeedsAttention(trustOf(user.id)))
        IdentityChangedAlert(user.id),
    if (roomAccessOf(room) != RoomAccess.public)
      for (final alert in recorded.whereType<UnvouchedDeviceAlert>())
        if (joined.contains(alert.userId)) alert,
  ];
}

({String title, String body}) newSignInText(
  AppLocalizations l10n,
  NewSignInAlert alert,
) => (
  title: l10n.securityNewSignInTitle,
  body: l10n.securityNewSignInBody(alert.label),
);

({String title, String body}) unvouchedDeviceText(
  AppLocalizations l10n,
  String name,
) => (
  title: l10n.securityUnvouchedDeviceTitle(name),
  body: l10n.securityUnvouchedDeviceBody,
);

({String title, String body}) recoveryResetText(AppLocalizations l10n) => (
  title: l10n.securityRecoveryResetTitle,
  body: l10n.securityRecoveryResetBody,
);
