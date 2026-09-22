import 'package:matrix/matrix.dart';

enum UserTrustState {
  noIdentity,
  unconfirmed,
  confirmed,
  confirmedWithPendingDevice,
  identityChanged,
}

UserTrustState userTrustState({
  required String? currentIdentityKey,
  required bool identityDirectlyVerified,
  required bool hasUnsignedDevices,
  required String? confirmedIdentityKey,
}) {
  if (currentIdentityKey == null) return UserTrustState.noIdentity;
  if (confirmedIdentityKey != null &&
      confirmedIdentityKey != currentIdentityKey) {
    return UserTrustState.identityChanged;
  }
  if (!identityDirectlyVerified) return UserTrustState.unconfirmed;
  return hasUnsignedDevices
      ? UserTrustState.confirmedWithPendingDevice
      : UserTrustState.confirmed;
}

({
  String? currentIdentityKey,
  bool identityDirectlyVerified,
  bool hasUnsignedDevices,
})
userTrustFactsOf(DeviceKeysList? keys) {
  final master = keys?.masterKey;
  return (
    currentIdentityKey: master?.ed25519Key,
    identityDirectlyVerified: master?.directVerified ?? false,
    hasUnsignedDevices: keys?.deviceKeys.values.any((d) => !d.signed) ?? false,
  );
}

bool userTrustNeedsAttention(UserTrustState state) =>
    state == UserTrustState.identityChanged;
