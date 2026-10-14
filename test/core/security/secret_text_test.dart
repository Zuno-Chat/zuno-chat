import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/security/secret_text.dart';
import 'package:zuno/core/security/sensitive_clipboard.dart';
import 'package:zuno/core/security/zuno_text_field.dart';

import '../../helpers/fake_calls_channel.dart';
import '../../helpers/native_method_calls.dart';
import '../../helpers/screen_security.dart';

const _mobile = TargetPlatformVariant({
  TargetPlatform.android,
  TargetPlatform.iOS,
});

void main() {
  late RecordedMethodCalls native;
  late List<String> plainCopies;

  setUp(() async {
    native = await installScreenSecurity(preventScreenshots: false);
    plainCopies = [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        plainCopies.add((call.arguments as Map)['text'] as String);
      }
      if (call.method == 'Clipboard.hasStrings') return {'value': true};
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
  });

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  );

  List<String> sensitiveCopies() => [
    for (final args in native.argsOf('copySensitive'))
      (args! as Map)['text'] as String,
  ];

  Set<ContextMenuButtonType> menu(WidgetTester tester) => {
    for (final item
        in tester
            .widget<AdaptiveTextSelectionToolbar>(
              find.byType(AdaptiveTextSelectionToolbar),
            )
            .buttonItems!)
      item.type,
  };

  bool screenReaderCanCopy(WidgetTester tester) =>
      tester.semantics.simulatedAccessibilityTraversal().any((node) {
        final data = node.getSemanticsData();
        return data.hasAction(SemanticsAction.copy) ||
            data.hasAction(SemanticsAction.cut);
      });

  Future<void> pressShortcut(
    WidgetTester tester,
    LogicalKeyboardKey key,
  ) async {
    final modifier = defaultTargetPlatform == TargetPlatform.iOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  group('SecretText', () {
    testWidgets('cannot be selected, so neither a menu nor a screen reader '
        'copies it', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, const SecretText('acorn'));

      await tester.longPress(find.byType(SecretText));
      await tester.pumpAndSettle();

      expect(screenReaderCanCopy(tester), isFalse);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      expect(plainCopies, isEmpty);
      semantics.dispose();
    }, variant: _mobile);

    testWidgets('stays out of a selection area around it', (tester) async {
      SelectedContent? selected;
      await pump(
        tester,
        SelectionArea(
          onSelectionChanged: (content) => selected = content,
          child: const SecretText('acorn'),
        ),
      );

      tester
          .state<SelectableRegionState>(find.byType(SelectableRegion))
          .selectAll();
      await tester.pump();

      expect(selected?.plainText ?? '', isEmpty);
    });

    testWidgets('protects the screen while it is shown', (tester) async {
      await pump(tester, const SecretText('acorn'));

      expect(native.screenshotBlocking, [true]);

      await tester.pumpWidget(const SizedBox());

      expect(native.screenshotBlocking, [true, false]);
    });
  });

  group('SecretTextField', () {
    late TextEditingController controller;

    setUp(() {
      controller = TextEditingController(text: 'acorn blew');
      addTearDown(controller.dispose);
    });

    Future<void> pumpField(WidgetTester tester) => pump(
      tester,
      SecretTextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'Recovery code'),
      ),
    );

    testWidgets('keeps typing out of the keyboard learning, suggestions and '
        'autocorrect', (tester) async {
      await pumpField(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enableIMEPersonalizedLearning, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.autocorrect, isFalse);
      expect(field.autofillHints, isNull);
    });

    testWidgets('keeps typing out of the keyboard learning where the app '
        'allows it', (tester) async {
      await pump(
        tester,
        KeyboardLearning(
          allowed: true,
          child: SecretTextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Recovery code'),
          ),
        ),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enableIMEPersonalizedLearning, isFalse);
    });

    Future<void> selectFirstWordAndShowMenu(WidgetTester tester) async {
      await tester.showKeyboard(find.byType(TextField));
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.pump();
      tester.state<EditableTextState>(find.byType(EditableText)).showToolbar();
      await tester.pumpAndSettle();
    }

    testWidgets('its menu keeps editing but never shares, looks up or '
        'searches, and Copy goes through the sensitive clipboard', (
      tester,
    ) async {
      await pumpField(tester);
      await selectFirstWordAndShowMenu(tester);

      expect(
        menu(tester),
        everyElement(
          isIn({
            ContextMenuButtonType.cut,
            ContextMenuButtonType.copy,
            ContextMenuButtonType.paste,
            ContextMenuButtonType.selectAll,
          }),
        ),
      );
      expect(
        menu(tester),
        containsAll([
          ContextMenuButtonType.cut,
          ContextMenuButtonType.copy,
          ContextMenuButtonType.paste,
        ]),
      );

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(sensitiveCopies(), ['acorn']);
      expect(controller.text, 'acorn blew');
      expect(plainCopies, isEmpty);
      await tester.pump(sensitiveClipboardLifetime);
    }, variant: _mobile);

    testWidgets('Cut in its menu goes through the sensitive clipboard', (
      tester,
    ) async {
      await pumpField(tester);
      await selectFirstWordAndShowMenu(tester);

      await tester.tap(find.text('Cut'));
      await tester.pumpAndSettle();

      expect(sensitiveCopies(), ['acorn']);
      expect(controller.text, ' blew');
      expect(plainCopies, isEmpty);
      await tester.pump(sensitiveClipboardLifetime);
    }, variant: _mobile);

    testWidgets('a keyboard copy and cut go through the sensitive clipboard', (
      tester,
    ) async {
      await pumpField(tester);
      await tester.showKeyboard(find.byType(TextField));
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.pump();

      await pressShortcut(tester, LogicalKeyboardKey.keyC);

      expect(sensitiveCopies(), ['acorn']);
      expect(controller.text, 'acorn blew');

      await pressShortcut(tester, LogicalKeyboardKey.keyX);

      expect(sensitiveCopies(), ['acorn', 'acorn']);
      expect(controller.text, ' blew');
      expect(plainCopies, isEmpty);
      await tester.pump(sensitiveClipboardLifetime);
    }, variant: _mobile);

    testWidgets('protects the screen while it is shown', (tester) async {
      await pumpField(tester);

      expect(native.screenshotBlocking, [true]);

      await tester.pumpWidget(const SizedBox());

      expect(native.screenshotBlocking, [true, false]);
    });
  });
}
