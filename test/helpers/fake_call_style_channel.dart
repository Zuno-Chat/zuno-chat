import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordedCallStyleCalls {
  final List<MethodCall> calls = [];

  MethodCall get lastShow =>
      calls.lastWhere((c) => c.method == 'showIncomingCallStyle');

  void clear() => calls.clear();
}

RecordedCallStyleCalls installFakeCallStyleChannel() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/call_style');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final recorded = RecordedCallStyleCalls();
  messenger.setMockMethodCallHandler(channel, (call) async {
    recorded.calls.add(call);
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return recorded;
}
