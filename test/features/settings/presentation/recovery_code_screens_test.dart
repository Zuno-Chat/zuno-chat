import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/security/recovery_code.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/features/settings/presentation/recovery_code_screens.dart';

import '../../../helpers/fake_attachments.dart';
import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/fixtures.dart';
import '../../../helpers/platform_capabilities.dart';

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1080, 2400),
  bool busy = false,
  PlatformCapabilities? capabilities,
  Future<RecoveryWordlist> Function()? wordlist,
  ValueChanged<String>? onComplete,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recoveryWordlistProvider.overrideWith(
          (ref) => wordlist?.call() ?? Future.value(shippedRecoveryWordlist()),
        ),
        if (capabilities != null)
          platformCapabilitiesProvider.overrideWithValue(capabilities),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: RecoveryCodeCreateFlow(
            busy: busy,
            onComplete: onComplete ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpConfirmStepWithKeyboard(WidgetTester tester) async {
  await _pump(tester, size: const Size(360, 640));
  final toConfirm = find.widgetWithText(FilledButton, 'Continue');
  await tester.ensureVisible(toConfirm);
  await tester.pumpAndSettle();
  await tester.tap(toConfirm);
  await tester.pumpAndSettle();
  tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Continue comes after the words and every way to save them', (
    tester,
  ) async {
    await _pump(tester, size: const Size(360, 640));

    expect(tester.takeException(), isNull);
    final button = find.widgetWithText(FilledButton, 'Continue');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(button).top,
      greaterThan(tester.getRect(find.text('Copy')).bottom),
    );
    expect(tester.getRect(button).width, 360 - 48);
  });

  testWidgets('a wrong word says so where it can be seen, above the keyboard', (
    tester,
  ) async {
    await _pumpConfirmStepWithKeyboard(tester);

    await tester.enterText(find.byType(TextField).first, 'notaword');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final mismatch = find.text('That does not match. Check your saved copy.');
    final error = tester.getRect(mismatch);
    final done = tester.getRect(find.widgetWithText(FilledButton, 'Done'));
    expect(error.top, greaterThanOrEqualTo(0));
    expect(error.bottom, lessThanOrEqualTo(done.top));
    expect(done.bottom, lessThanOrEqualTo(640 - 300));
    expect(
      find.ancestor(of: mismatch, matching: find.byType(Scrollable)),
      findsNothing,
    );
  });

  testWidgets('reveals every word of the code, numbered by position so the '
      'confirm step can ask for one', (tester) async {
    await _pump(tester);

    final wordlist = shippedRecoveryWordlist();
    final shown = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.data)
        .whereType<String>()
        .toList();

    expect(shown, hasLength(recoveryCodeWordCount));
    for (final word in shown) {
      expect(wordlist.contains(word), isTrue, reason: word);
    }
    for (var i = 1; i <= recoveryCodeWordCount; i++) {
      expect(find.text('$i'), findsOneWidget, reason: 'position $i');
    }
  });

  testWidgets('falls back to one column on a narrow screen', (tester) async {
    await _pump(tester, size: const Size(320, 1400));

    final words = find.byType(SelectableText);
    expect(words, findsNWidgets(recoveryCodeWordCount));
    expect({
      for (final word in words.evaluate())
        tester.getTopLeft(find.byWidget(word.widget)).dx,
    }, hasLength(1));
  });

  testWidgets('asks for two words by position before finishing', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Check your saved copy'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Show the code again'), findsOneWidget);
  });

  group('making a code', () {
    late List<String> completed;

    Future<void> pumpFlow(
      WidgetTester tester, {
      bool busy = false,
      PlatformCapabilities? capabilities,
      Future<RecoveryWordlist> Function()? wordlist,
    }) {
      completed = [];
      return _pump(
        tester,
        busy: busy,
        capabilities: capabilities,
        wordlist: wordlist,
        onComplete: completed.add,
      );
    }

    List<String> shownWords(WidgetTester tester) => tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.data!)
        .toList();

    List<int> askedPositions(WidgetTester tester) => [
      for (final field in tester.widgetList<TextField>(find.byType(TextField)))
        int.parse(
          RegExp(r'\d+').firstMatch(field.decoration!.labelText!)!.group(0)!,
        ),
    ];

    Future<List<String>> toConfirm(WidgetTester tester) async {
      final words = shownWords(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      return words;
    }

    testWidgets('a wordlist that cannot load says to go back', (tester) async {
      await pumpFlow(tester, wordlist: () async => throw Exception('missing'));

      expect(
        find.text('Could not prepare a recovery code. Go back and try again.'),
        findsOneWidget,
      );
      expect(find.text('Continue'), findsNothing);
    });

    testWidgets('the asked words finish with the code that was shown', (
      tester,
    ) async {
      await pumpFlow(tester);
      final words = await toConfirm(tester);
      final positions = askedPositions(tester);

      final fields = find.byType(TextField);
      for (var i = 0; i < positions.length; i++) {
        await tester.enterText(
          fields.at(i),
          '  ${words[positions[i] - 1].toUpperCase()} ',
        );
      }
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(completed, [words.join(' ')]);
      expect(find.textContaining('does not match'), findsNothing);
    });

    testWidgets('Show the code again brings back the same words', (
      tester,
    ) async {
      await pumpFlow(tester);
      final words = await toConfirm(tester);

      await tester.tap(find.text('Show the code again'));
      await tester.pumpAndSettle();

      expect(shownWords(tester), words);
    });

    testWidgets('while it is being saved nothing can be pressed', (
      tester,
    ) async {
      await pumpFlow(tester, busy: true);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final done = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(done.onPressed, isNull);
      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Show the code again'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('Save to password manager offers the code for saving', (
      tester,
    ) async {
      final textInput = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        (call) async {
          textInput.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.textInput,
          null,
        ),
      );
      await pumpFlow(tester);
      final code = shownWords(tester).join(' ');

      await tester.tap(find.text('Save to password manager'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller!.text, code);
      expect(field.readOnly, isTrue);
      expect(field.autofillHints, [AutofillHints.newPassword]);

      await tester.tap(find.widgetWithText(TextButton, 'Done'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(textInput, contains('TextInput.finishAutofillContext'));
    });

    group('Save as a file', () {
      late FakeFilePicker picker;

      setUp(() => picker = installFakeFilePicker());

      testWidgets('writes the code to a text file', (tester) async {
        await pumpFlow(tester);
        final code = shownWords(tester).join(' ');

        await tester.tap(find.text('Save as a file'));
        await tester.pumpAndSettle();

        final saved = picker.saved.single;
        expect(saved.fileName, 'zuno-recovery-code.txt');
        expect(saved.mimeType, 'text/plain');
        expect(utf8.decode(saved.bytes), '$code\n');
        expect(find.text('Saved'), findsOneWidget);
      });

      testWidgets('a cancelled save says nothing', (tester) async {
        picker.answer = null;
        await pumpFlow(tester);

        await tester.tap(find.text('Save as a file'));
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsNothing);
      });

      testWidgets('a failed save says so', (tester) async {
        picker.saveError = PlatformException(code: 'no_space');
        await pumpFlow(tester);

        await tester.tap(find.text('Save as a file'));
        await tester.pumpAndSettle();

        expect(find.text('Could not save. Try again.'), findsOneWidget);
      });
    });

    group('Copy', () {
      late List<MethodCall> calls;
      late List<String?> plainCopies;

      setUp(() {
        plainCopies = [];
        calls = installFakeCallsChannel().calls;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            plainCopies.add((call.arguments as Map)['text'] as String?);
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
      });

      Future<void> expectCopyClearsAfter90Seconds(
        WidgetTester tester,
        PlatformCapabilities capabilities,
      ) async {
        await pumpFlow(tester, capabilities: capabilities);
        final code = shownWords(tester).join(' ');

        await tester.tap(find.text('Copy'));
        await tester.pump();

        expect(calls.single.method, 'copySensitive');
        expect(calls.single.arguments, {'text': code});
        expect(
          find.text('Copied. Clears from the clipboard in 90 seconds.'),
          findsOneWidget,
        );

        await tester.pump(const Duration(seconds: 90));

        expect(calls.last.method, 'clearClipboardIfMatches');
        await tester.pumpAndSettle();
      }

      testWidgets('on Android the copy clears itself after 90 seconds', (
        tester,
      ) async {
        await expectCopyClearsAfter90Seconds(tester, androidCapabilities);
      });

      testWidgets('on iOS the copy also clears itself after 90 seconds', (
        tester,
      ) async {
        ambientCapabilities = iosCapabilities;
        await expectCopyClearsAfter90Seconds(tester, iosCapabilities);
      });

      testWidgets('without a sensitive clipboard it promises no clearing it '
          'cannot do', (tester) async {
        final plain = capabilitiesLike(
          androidCapabilities,
          sensitiveClipboard: false,
        );
        ambientCapabilities = plain;
        await pumpFlow(tester, capabilities: plain);
        final code = shownWords(tester).join(' ');

        await tester.tap(find.text('Copy'));
        await tester.pump();

        expect(plainCopies, [code]);
        expect(find.textContaining('90 seconds'), findsNothing);
        expect(
          find.text(
            'Copied. It stays on the clipboard until you copy something '
            'else.',
          ),
          findsOneWidget,
        );
        await tester.pumpAndSettle();
      });
    });
  });

  group('entering a code', () {
    late int submits;

    Future<void> pumpField(WidgetTester tester, {bool busy = false}) async {
      submits = 0;
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recoveryWordlistProvider.overrideWith(
              (ref) async => shippedRecoveryWordlist(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: RecoveryCodeEntryField(
                controller: controller,
                error: null,
                busy: busy,
                onSubmit: () => submits++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    List<String> validWords(int count) =>
        shippedRecoveryWordlist().words.take(count).toList();

    for (final (name, typed, hint) in [
      ('a full code looks right', validWords(12).join(' '), 'Looks right.'),
      (
        'one word too many says how many a code has',
        validWords(13).join(' '),
        'That is 13 words. A code has 12.',
      ),
      (
        'one word short counts it down',
        validWords(11).join(' '),
        '1 more word to go.',
      ),
      (
        'only punctuation counts as no words yet',
        '--- ...',
        '12 more words to go.',
      ),
    ]) {
      testWidgets(name, (tester) async {
        await pumpField(tester);

        await tester.enterText(find.byType(TextField), typed);
        await tester.pump();

        expect(find.text(hint), findsOneWidget);
      });
    }

    testWidgets('the keyboard action submits', (tester) async {
      await pumpField(tester);

      await tester.showKeyboard(find.byType(TextField));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(submits, 1);
    });

    testWidgets('the keyboard action waits while busy', (tester) async {
      await pumpField(tester, busy: true);

      await tester.showKeyboard(find.byType(TextField));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(submits, 0);
    });

    group('Open a saved file', () {
      late FakeFilePicker picker;

      setUp(() => picker = installFakeFilePicker());

      String fieldText(WidgetTester tester) =>
          tester.widget<TextField>(find.byType(TextField)).controller!.text;

      testWidgets('fills in the code from the saved file', (tester) async {
        final code = validWords(12).join(' ');
        picker.picked = [
          FakePickedFile(
            'zuno-recovery-code.txt',
            Uint8List.fromList(utf8.encode('$code\n')),
          ),
        ];
        await pumpField(tester);

        await tester.tap(find.text('Open a saved file'));
        await tester.pumpAndSettle();

        expect(fieldText(tester), code);
        expect(find.text('Looks right.'), findsOneWidget);
        expect(submits, 0);
      });

      testWidgets('spins while the saved file is on its way', (tester) async {
        final code = validWords(12).join(' ');
        picker
          ..copying = Completer<void>()
          ..picked = [
            FakePickedFile(
              'zuno-recovery-code.txt',
              Uint8List.fromList(utf8.encode('$code\n')),
            ),
          ];
        await pumpField(tester);

        await tester.tap(find.text('Open a saved file'));
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byIcon(Icons.file_open_outlined), findsNothing);

        picker.copying!.complete();
        await tester.pumpAndSettle();

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(fieldText(tester), code);
      });

      testWidgets('a cancelled pick changes nothing', (tester) async {
        await pumpField(tester);

        await tester.tap(find.text('Open a saved file'));
        await tester.pumpAndSettle();

        expect(fieldText(tester), isEmpty);
        expect(find.byType(SnackBar), findsNothing);
      });

      testWidgets('a file without a code says so', (tester) async {
        picker.picked = [
          FakePickedFile(
            'photo.jpg',
            Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
          ),
        ];
        await pumpField(tester);

        await tester.tap(find.text('Open a saved file'));
        await tester.pumpAndSettle();

        expect(fieldText(tester), isEmpty);
        expect(
          find.text('That file does not hold a recovery code.'),
          findsOneWidget,
        );
      });

      testWidgets('a picker failure says so', (tester) async {
        picker.pickError = PlatformException(code: 'unknown_path');
        await pumpField(tester);

        await tester.tap(find.text('Open a saved file'));
        await tester.pumpAndSettle();

        expect(
          find.text('Could not open that file. Try again.'),
          findsOneWidget,
        );
      });

      testWidgets('waits while busy', (tester) async {
        await pumpField(tester, busy: true);

        await tester.tap(find.text('Open a saved file'));
        await tester.pumpAndSettle();

        expect(picker.picks, 0);
      });
    });
  });
}
