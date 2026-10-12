import 'dart:async';

import 'package:flutter/services.dart';

import 'native_method_calls.dart';

RecordedMethodCalls installFakeFilesChannel({
  FutureOr<Object?> Function(MethodCall call)? reply,
}) => recordMethodChannel('zuno/files', reply: reply);
