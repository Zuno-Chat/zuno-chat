import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/platform/app_platform.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/security/sensitive_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/calls');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> native;
  late List<String> clipboardWrites;
  Object? nativeError;

  setUp(() {
    native = [];
    clipboardWrites = [];
    nativeError = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      native.add(call);
      final error = nativeError;
      if (error != null) throw error;
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardWrites.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    SensitiveClipboard.instance.cancelPendingClear();
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('copies through the native side, then clears once it expires', () {
    fakeAsync((async) {
      SensitiveClipboard.instance.copy('recovery code');
      async.flushMicrotasks();

      expect(native.map((c) => c.method), ['copySensitive']);
      expect(native.single.arguments, {'text': 'recovery code'});
      expect(clipboardWrites, isEmpty);

      async.elapse(sensitiveClipboardLifetime);

      expect(native.map((c) => c.method), [
        'copySensitive',
        'clearClipboardIfMatches',
      ]);
      expect(native.last.arguments, {'text': 'recovery code'});
    });
  });

  test('a native refusal still copies the code', () async {
    nativeError = PlatformException(code: 'denied');

    await SensitiveClipboard.instance.copy('recovery code');

    expect(clipboardWrites, ['recovery code']);
  });

  test('no native side at all still copies the code', () async {
    messenger.setMockMethodCallHandler(channel, null);

    await SensitiveClipboard.instance.copy('recovery code');

    expect(clipboardWrites, ['recovery code']);
  });

  test('a platform without a sensitive clipboard copies plainly and never '
      'calls native', () {
    fakeAsync((async) {
      SensitiveClipboard(capabilities: capabilitiesFor(AppPlatform.ios))
          .copy('recovery code');
      async.flushMicrotasks();

      expect(clipboardWrites, ['recovery code']);

      async.elapse(sensitiveClipboardLifetime * 2);

      expect(native, isEmpty);
    });
  });
}
