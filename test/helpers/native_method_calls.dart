import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Object?> callFromNative(
  MethodChannel channel,
  String method, [
  Object? arguments,
]) {
  final replied = Completer<Object?>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall(method, arguments)),
        (data) {
          try {
            replied.complete(
              data == null ? null : channel.codec.decodeEnvelope(data),
            );
          } catch (error) {
            replied.completeError(error);
          }
        },
      );
  return replied.future;
}

void silenceMethodChannels(Iterable<String> names) {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in names) {
    final channel = MethodChannel(name);
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }
}

class RecordedMethodCalls {
  final calls = <MethodCall>[];

  List<String> get methods => [for (final call in calls) call.method];

  Iterable<MethodCall> named(String method) =>
      calls.where((call) => call.method == method);

  List<Object?> argsOf(String method) => [
    for (final call in named(method)) call.arguments,
  ];

  int count(String method) => named(method).length;

  void clear() => calls.clear();
}

RecordedMethodCalls recordMethodChannel(
  String name, {
  FutureOr<Object?> Function(MethodCall call)? reply,
}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  final channel = MethodChannel(name);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final recorded = RecordedMethodCalls();
  messenger.setMockMethodCallHandler(channel, (call) async {
    recorded.calls.add(call);
    return reply?.call(call);
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return recorded;
}
