import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_method_calls.dart';

const _callsChannel = MethodChannel('zuno/calls');

RecordedMethodCalls installFakeCallsChannel({
  FutureOr<Object?> Function(MethodCall call)? reply,
}) => recordMethodChannel(_callsChannel.name, reply: reply);

extension CallsChannelReadings on RecordedMethodCalls {
  List<bool> get screenshotBlocking => [
    for (final args in argsOf('setPreventScreenshots'))
      (args! as Map)['enabled'] as bool,
  ];
}

void removeCallsChannel() => TestDefaultBinaryMessengerBinding
    .instance
    .defaultBinaryMessenger
    .setMockMethodCallHandler(_callsChannel, null);

Future<Object?> sendFromNative(String method, [Object? arguments]) =>
    callFromNative(_callsChannel, method, arguments);
