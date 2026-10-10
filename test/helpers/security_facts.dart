import 'package:zuno/core/security/account_security_status.dart';

AccountSecurityFacts securityFacts({
  bool recoveryExists = true,
  bool thisDeviceHasIdentityKeys = true,
  bool keyBackupExists = true,
  bool keyBackupUsableHere = true,
  int unapprovedOtherDevices = 0,
}) => AccountSecurityFacts(
  recoveryExists: recoveryExists,
  thisDeviceHasIdentityKeys: thisDeviceHasIdentityKeys,
  keyBackupExists: keyBackupExists,
  keyBackupUsableHere: keyBackupUsableHere,
  unapprovedOtherDevices: unapprovedOtherDevices,
);
