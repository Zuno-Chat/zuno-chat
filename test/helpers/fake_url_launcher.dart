import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> mockUrlLauncher(
  WidgetTester tester, {
  Future<Object?> Function()? answer,
}) {
  final launched = <String>[];
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method != 'launch') return null;
    launched.add((call.arguments as Map<Object?, Object?>)['url']! as String);
    return answer == null ? true : await answer();
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return launched;
}
