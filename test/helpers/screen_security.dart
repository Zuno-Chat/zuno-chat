import 'package:zuno/core/security/screen_security_service.dart';

import 'fake_calls_channel.dart';
import 'native_method_calls.dart';

Future<RecordedMethodCalls> installScreenSecurity({
  required bool preventScreenshots,
}) async {
  final native = installFakeCallsChannel();
  await ScreenSecurityService.instance.followPreference(preventScreenshots);
  native.clear();
  return native;
}
