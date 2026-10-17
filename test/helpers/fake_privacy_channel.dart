import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_method_calls.dart';

const _privacyChannel = MethodChannel('zuno/privacy');

RecordedMethodCalls installFakePrivacyChannel({
  FutureOr<Object?> Function(MethodCall call)? reply,
}) => recordMethodChannel(_privacyChannel.name, reply: reply);

extension PrivacyChannelReadings on RecordedMethodCalls {
  List<bool> _flagsOf(String method, [String key = 'enabled']) => [
    for (final args in argsOf(method)) (args! as Map)[key] as bool,
  ];

  List<bool> get screenshotBlocking => _flagsOf('setPreventScreenshots');

  List<bool> get overlayHiding => _flagsOf('setHideOverlays');

  List<bool> get accessibilitySensitivity =>
      _flagsOf('setAccessibilitySensitive');

  List<bool> get thirdPartyKeyboards =>
      _flagsOf('setThirdPartyKeyboards', 'allowed');
}

void removePrivacyChannel() => TestDefaultBinaryMessengerBinding
    .instance
    .defaultBinaryMessenger
    .setMockMethodCallHandler(_privacyChannel, null);
