import 'package:flutter/foundation.dart';

import '../account_security_status.dart';

sealed class SecurityAlert {
  const SecurityAlert();
}

sealed class RecordedSecurityAlert extends SecurityAlert {
  const RecordedSecurityAlert();

  String get key;
}

final class RecoveryResetAlert extends RecordedSecurityAlert {
  final String identityKey;

  const RecoveryResetAlert(this.identityKey);

  @override
  String get key => 'recoveryReset';

  @override
  bool operator ==(Object other) =>
      other is RecoveryResetAlert && other.identityKey == identityKey;

  @override
  int get hashCode => identityKey.hashCode;
}

final class NewSignInAlert extends RecordedSecurityAlert {
  final String deviceId;
  final String? displayName;
  final String? ipAddress;
  final DateTime? seenAt;

  const NewSignInAlert({
    required this.deviceId,
    this.displayName,
    this.ipAddress,
    this.seenAt,
  });

  @override
  String get key => 'newSignIn:$deviceId';

  String get label {
    final name = displayName?.trim() ?? '';
    return name.isEmpty ? deviceId : name;
  }

  @override
  bool operator ==(Object other) =>
      other is NewSignInAlert &&
      other.deviceId == deviceId &&
      other.displayName == displayName &&
      other.ipAddress == ipAddress &&
      other.seenAt == seenAt;

  @override
  int get hashCode => Object.hash(deviceId, displayName, ipAddress, seenAt);
}

final class UnvouchedDeviceAlert extends RecordedSecurityAlert {
  final String userId;
  final Set<String> deviceIds;

  const UnvouchedDeviceAlert({required this.userId, required this.deviceIds});

  @override
  String get key => 'unvouchedDevice:$userId';

  @override
  bool operator ==(Object other) =>
      other is UnvouchedDeviceAlert &&
      other.userId == userId &&
      setEquals(other.deviceIds, deviceIds);

  @override
  int get hashCode => Object.hash(userId, Object.hashAllUnordered(deviceIds));
}

final class IdentityChangedAlert extends SecurityAlert {
  final String userId;

  const IdentityChangedAlert(this.userId);

  @override
  bool operator ==(Object other) =>
      other is IdentityChangedAlert && other.userId == userId;

  @override
  int get hashCode => userId.hashCode;
}

final class AccountStatusAlert extends SecurityAlert {
  final AccountSecurityStatus status;

  const AccountStatusAlert(this.status);

  @override
  bool operator ==(Object other) =>
      other is AccountStatusAlert && other.status == status;

  @override
  int get hashCode => status.hashCode;
}
