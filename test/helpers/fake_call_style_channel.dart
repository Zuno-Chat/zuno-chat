import 'package:flutter/services.dart';

import 'native_method_calls.dart';

RecordedMethodCalls installFakeCallStyleChannel() =>
    recordMethodChannel('zuno/call_style');

extension CallStyleReadings on RecordedMethodCalls {
  MethodCall get lastShow => named('showIncomingCallStyle').last;
}
