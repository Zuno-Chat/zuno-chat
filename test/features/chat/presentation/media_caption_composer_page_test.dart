import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/features/chat/presentation/media_caption_composer_page.dart';

final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

void main() {
  testWidgets('single image: no page indicator, empty caption sends fine', (
    tester,
  ) async {
    List<ComposedMedia>? result;
    final items = [PickedImage(name: 'a.jpg', bytes: _onePixelPng)];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<List<ComposedMedia>>(
                MaterialPageRoute(
                  builder: (_) => MediaCaptionComposerPage(items: items),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Add a caption'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(result, hasLength(1));
    final image = (result!.single as ComposedImageResult).image;
    expect(image.name, 'a.jpg');
    expect(image.caption, '');
  });

  testWidgets(
    'multiple images: swipe, per-page caption, send preserves order',
    (tester) async {
      List<ComposedMedia>? result;
      final items = [
        PickedImage(name: 'first.jpg', bytes: _onePixelPng),
        PickedImage(name: 'second.jpg', bytes: _onePixelPng),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push<List<ComposedMedia>>(
                  MaterialPageRoute(
                    builder: (_) => MediaCaptionComposerPage(items: items),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('1 of 2'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'first caption');
      await tester.pumpAndSettle();

      await tester.drag(find.byType(PageView), const Offset(-800, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 of 2'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'second caption');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(result, hasLength(2));
      final first = (result![0] as ComposedImageResult).image;
      final second = (result![1] as ComposedImageResult).image;
      expect(first.name, 'first.jpg');
      expect(first.caption, 'first caption');
      expect(second.name, 'second.jpg');
      expect(second.caption, 'second caption');
    },
  );

  testWidgets('removing the only remaining item pops with no result (cancel)', (
    tester,
  ) async {
    List<ComposedMedia>? result;
    var popped = false;
    final items = [PickedImage(name: 'only.jpg', bytes: _onePixelPng)];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<List<ComposedMedia>>(
                MaterialPageRoute(
                  builder: (_) => MediaCaptionComposerPage(items: items),
                ),
              );
              popped = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(popped, isTrue);
    expect(result, isNull);
  });

  testWidgets('removing one of several items drops it from the sent result', (
    tester,
  ) async {
    List<ComposedMedia>? result;
    final items = [
      PickedImage(name: 'removed.jpg', bytes: _onePixelPng),
      PickedImage(name: 'kept.jpg', bytes: _onePixelPng),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<List<ComposedMedia>>(
                MaterialPageRoute(
                  builder: (_) => MediaCaptionComposerPage(items: items),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Add a caption'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(result, hasLength(1));
    expect((result!.single as ComposedImageResult).image.name, 'kept.jpg');
  });
}
