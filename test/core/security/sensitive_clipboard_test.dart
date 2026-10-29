import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/security/sensitive_clipboard.dart';

import '../../helpers/app_lifecycle.dart';
import '../../helpers/fake_privacy_channel.dart';
import '../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> native;
  late List<String> clipboardWrites;
  Object? nativeError;
  late List<bool?> clearReplies;

  setUp(() {
    clipboardWrites = [];
    nativeError = null;
    clearReplies = [];
    native = installFakePrivacyChannel(
      reply: (call) {
        final error = nativeError;
        if (error != null) throw error;
        if (call.method == 'clearClipboardIfMatches' &&
            clearReplies.isNotEmpty) {
          return clearReplies.removeAt(0);
        }
        return null;
      },
    ).calls;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardWrites.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    SensitiveClipboard.instance.cancelPendingClear();
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

  List<String> clears() => [
    for (final call in native)
      if (call.method == 'clearClipboardIfMatches')
        (call.arguments as Map)['text'] as String,
  ];

  void resumeFromBackground(FakeAsync async) {
    final binding = WidgetsBinding.instance;
    moveLifecycleTo(binding, AppLifecycleState.paused);
    moveLifecycleTo(binding, AppLifecycleState.resumed);
    async.flushMicrotasks();
  }

  test('a clipboard native code cannot read yet is cleared on the next '
      'resume, still only if it holds the code', () {
    fakeAsync((async) {
      clearReplies = [true, false];
      SensitiveClipboard.instance.copy('recovery code');
      async.elapse(sensitiveClipboardLifetime);

      expect(clears(), ['recovery code']);

      async.elapse(const Duration(minutes: 10));
      expect(clears(), ['recovery code']);

      resumeFromBackground(async);
      expect(clears(), ['recovery code', 'recovery code']);

      resumeFromBackground(async);
      expect(clears(), hasLength(2));
    });
  });

  test('a clear the native side ran is never repeated on resume', () {
    fakeAsync((async) {
      SensitiveClipboard.instance.copy('recovery code');
      async.elapse(sensitiveClipboardLifetime);

      resumeFromBackground(async);

      expect(clears(), ['recovery code']);
    });
  });

  test('a new copy replaces a clear still waiting for a resume', () {
    fakeAsync((async) {
      clearReplies = [true];
      SensitiveClipboard.instance.copy('old code');
      async.elapse(sensitiveClipboardLifetime);

      SensitiveClipboard.instance.copy('new code');
      async.flushMicrotasks();
      resumeFromBackground(async);

      expect(clears(), ['old code']);

      async.elapse(sensitiveClipboardLifetime);
      expect(clears(), ['old code', 'new code']);
    });
  });

  test('a native refusal still copies the code', () async {
    nativeError = PlatformException(code: 'denied');

    await SensitiveClipboard.instance.copy('recovery code');

    expect(clipboardWrites, ['recovery code']);
  });

  test('no native side at all still copies the code', () async {
    removePrivacyChannel();

    await SensitiveClipboard.instance.copy('recovery code');

    expect(clipboardWrites, ['recovery code']);
  });

  test('a platform without a sensitive clipboard copies plainly and never '
      'calls native', () {
    fakeAsync((async) {
      SensitiveClipboard(
        capabilities: capabilitiesLike(
          androidCapabilities,
          sensitiveClipboard: false,
        ),
      ).copy('recovery code');
      async.flushMicrotasks();

      expect(clipboardWrites, ['recovery code']);

      async.elapse(sensitiveClipboardLifetime * 2);

      expect(native, isEmpty);
    });
  });

  testWidgets('the copy notice says the clipboard clears only where it '
      'does', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: Text('Backup')),
      ),
    );
    final context = tester.element(find.text('Backup'));
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);

    final clearing = SensitiveClipboard(
      capabilities: capabilitiesLike(
        androidCapabilities,
        sensitiveClipboard: true,
      ),
    );
    await clearing.copyWithNotice(messenger, l10n, 'recovery code');
    await tester.pump();
    expect(find.text(l10n.settingsCopiedSensitive), findsOneWidget);

    messenger.removeCurrentSnackBar();
    await tester.pumpAndSettle();

    await SensitiveClipboard(
      capabilities: capabilitiesLike(
        androidCapabilities,
        sensitiveClipboard: false,
      ),
    ).copyWithNotice(messenger, l10n, 'recovery code');
    await tester.pump();
    expect(find.text(l10n.settingsCopiedStays), findsOneWidget);
    clearing.cancelPendingClear();
  });
}
