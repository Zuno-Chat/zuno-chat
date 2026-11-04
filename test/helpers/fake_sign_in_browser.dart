import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('flutter_web_auth_2');

List<String> mockSignInBrowser(
  WidgetTester tester, {
  Future<Object?> Function()? answer,
}) {
  final opened = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_channel, (call) async {
    if (call.method != 'authenticate') return null;
    final arguments = call.arguments as Map<Object?, Object?>;
    opened.add(arguments['url']! as String);
    if (answer != null) return answer();
    throw PlatformException(code: 'CANCELED');
  });
  addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
  return opened;
}

Future<Object?> noSignInBrowser() async =>
    throw PlatformException(code: 'NO_BROWSER');
