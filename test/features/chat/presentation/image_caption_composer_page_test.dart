import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/keep_clear.dart';
import 'package:zuno/features/chat/presentation/image_caption_composer_page.dart';

final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

void main() {
  List<ComposedImage>? result;
  var closed = false;

  setUp(() {
    result = null;
    closed = false;
  });

  Future<void> open(WidgetTester tester, List<String> names) async {
    final images = [
      for (final name in names)
        (bytes: Uint8List.fromList(_onePixelPng), name: name),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<List<ComposedImage>>(
                MaterialPageRoute(
                  builder: (_) => ImageCaptionComposerPage(images: images),
                ),
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> swipeNext(WidgetTester tester) async {
    await tester.drag(find.byType(PageView), const Offset(-800, 0));
    await tester.pumpAndSettle();
  }

  Future<void> remove(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Remove this photo'));
    await tester.pumpAndSettle();
  }

  testWidgets('one photo asks for a caption and sends it trimmed', (
    tester,
  ) async {
    await open(tester, ['a.jpg']);

    expect(find.text('Add a caption'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);

    await tester.enterText(find.byType(TextField), ' sunset  ');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(result!.single.name, 'a.jpg');
    expect(result!.single.caption, 'sunset');
    expect(result!.single.bytes, _onePixelPng);
  });

  testWidgets('several photos each keep their own caption, in order', (
    tester,
  ) async {
    await open(tester, ['a.jpg', 'b.jpg']);

    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.byTooltip('Send all'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'first');
    await swipeNext(tester);
    expect(find.text('2 of 2'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    await tester.enterText(find.byType(TextField), 'second');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      [for (final i in result!) (i.name, i.caption)],
      [('a.jpg', 'first'), ('b.jpg', 'second')],
    );
  });

  testWidgets('removing the last photo steps back to the one before', (
    tester,
  ) async {
    await open(tester, ['a.jpg', 'b.jpg', 'c.jpg']);
    await swipeNext(tester);
    await tester.enterText(find.byType(TextField), 'keep me');
    await swipeNext(tester);
    expect(find.text('3 of 3'), findsOneWidget);

    await remove(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('2 of 2'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'keep me',
    );

    await tester.tap(find.byTooltip('Send all'));
    await tester.pumpAndSettle();

    expect([for (final i in result!) i.name], ['a.jpg', 'b.jpg']);
  });

  testWidgets('removing down to one drops the counter', (tester) async {
    await open(tester, ['a.jpg', 'b.jpg']);

    await remove(tester);

    expect(find.text('Add a caption'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
  });

  testWidgets('removing the only photo closes without sending', (tester) async {
    await open(tester, ['a.jpg']);

    await remove(tester);

    expect(closed, isTrue);
    expect(result, isNull);
  });

  testWidgets('the floating call window keeps clear of the caption bar', (
    tester,
  ) async {
    await open(tester, ['a.png']);

    expect(
      find.ancestor(
        of: find.byTooltip('Send'),
        matching: find.byType(KeepClearArea),
      ),
      findsOneWidget,
    );
  });
}
