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
  required bool identityConfirmed,
  required bool hasUnsignedDevices,
  required String? confirmedIdentityKey,
}) {
  if (currentIdentityKey == null) return UserTrustState.noIdentity;
  if (confirmedIdentityKey != null &&
      confirmedIdentityKey != currentIdentityKey) {
    return UserTrustState.identityChanged;
  }
  if (!identityConfirmed) return UserTrustState.unconfirmed;
  return hasUnsignedDevices
      ? UserTrustState.confirmedWithPendingDevice
      : UserTrustState.confirmed;
}

({String? currentIdentityKey, bool identityConfirmed, bool hasUnsignedDevices})
userTrustFactsOf(DeviceKeysList? keys) {
  final master = keys?.masterKey;
  return (
    currentIdentityKey: master?.ed25519Key,
    identityConfirmed: master != null && confirmedByOwnAccount(master),
    hasUnsignedDevices: keys?.deviceKeys.values.any((d) => !d.signed) ?? false,
  );
}

bool confirmedByOwnAccount(CrossSigningKey identity) {
  if (identity.directVerified) return true;
  final client = identity.client;
  final ownId = client.userID;
  final ownSignatures = identity.signatures?[ownId];
  if (ownId == null || ownSignatures == null) return false;
  final vouched = CrossSigningKey.fromJson({
    ...identity.toJson(),
    'signatures': {ownId: ownSignatures},
  }, client)..validSignatures = identity.validSignatures ??= {};
  return vouched.hasValidSignatureChain();
}

bool deviceApprovedByOwner(DeviceKeys? device) =>
    device?.hasValidSignatureChain(verifiedByTheirMasterKey: true) ?? false;

bool userTrustConfirmed(UserTrustState state) => switch (state) {
  UserTrustState.confirmed || UserTrustState.confirmedWithPendingDevice => true,
  UserTrustState.noIdentity ||
  UserTrustState.unconfirmed ||
  UserTrustState.identityChanged => false,
};

bool userTrustNeedsAttention(UserTrustState state) =>
    state == UserTrustState.identityChanged;
