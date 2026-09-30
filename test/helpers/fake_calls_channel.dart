import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _callsChannel = MethodChannel('zuno/calls');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

class RecordedCallsChannel {
  final calls = <MethodCall>[];

  List<String> get methods => [for (final call in calls) call.method];

  List<Object?> argsOf(String method) => [
    for (final call in calls)
      if (call.method == method) call.arguments,
  ];

  int count(String method) => argsOf(method).length;

  void clear() => calls.clear();
}

RecordedCallsChannel installFakeCallsChannel({
  FutureOr<Object?> Function(MethodCall call)? reply,
}) {
  final recorded = RecordedCallsChannel();
  _messenger.setMockMethodCallHandler(_callsChannel, (call) async {
    recorded.calls.add(call);
    return reply?.call(call);
  });
  addTearDown(() => _messenger.setMockMethodCallHandler(_callsChannel, null));
  return recorded;
}

Future<void> sendFromNative(String method, [Object? arguments]) =>
    _messenger.handlePlatformMessage(
      _callsChannel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      null,
    );
