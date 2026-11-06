import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno_emoji/src/drawable_probe.dart';
import 'package:zuno_emoji/src/emoji_support.dart';

import 'helpers.dart';

void main() {
  group('EmojiSupport', () {
    late MemoryEmojiStore store;
    late List<List<String>> probed;

    Future<List<bool>> probe(List<String> emoji) async {
      probed.add(emoji);
      return [for (final e in emoji) e != '🫫' && e != '👋🏿'];
    }

    setUp(() {
      store = MemoryEmojiStore();
      probed = [];
    });

    test(
      'probes newer emoji and every variant once and caches the result',
      () async {
        final support = EmojiSupport(
          store: store,
          environment: 'os1',
          probe: probe,
        );
        final undrawable = await support.undrawable();
        expect(undrawable, {'🫫', '👋🏿'});
        expect(probed.single, containsAll(['🫫', '🥰', '👋🏻', '👋🏿']));
        expect(await support.undrawable(), same(undrawable));
        expect(probed, hasLength(1));
      },
    );

    test('emoji up to Emoji 5.0 are drawable without probing', () async {
      await EmojiSupport(
        store: store,
        environment: 'os1',
        probe: (emoji) async => [for (final _ in emoji) false],
      ).undrawable().then((undrawable) {
        expect(undrawable, isNot(contains('😀')));
        expect(undrawable, isNot(contains('♥️')));
        expect(undrawable, containsAll(['🥰', '👋🏻']));
      });
      await EmojiSupport(
        store: MemoryEmojiStore(),
        environment: 'os1',
        probe: probe,
      ).undrawable();
      expect(probed.single, isNot(contains('😀')));
      expect(probed.single, isNot(contains('👋')));
    });

    test('a later start in the same environment reads the cache', () async {
      await EmojiSupport(
        store: store,
        environment: 'os1',
        probe: probe,
      ).undrawable();
      probed.clear();
      final again = EmojiSupport(
        store: store,
        environment: 'os1',
        probe: probe,
      );
      expect(await again.undrawable(), {'🫫', '👋🏿'});
      expect(probed, isEmpty);
    });

    test('a new environment probes again', () async {
      await EmojiSupport(
        store: store,
        environment: 'os1',
        probe: probe,
      ).undrawable();
      probed.clear();
      await EmojiSupport(
        store: store,
        environment: 'os2',
        probe: probe,
      ).undrawable();
      expect(probed, hasLength(1));
    });

    test('a failed probe hides new emoji and every tone, reports, and caches nothing', () async {
      Object? reported;
      final support = EmojiSupport(
        store: store,
        environment: 'os1',
        probe: (_) => Future.error(StateError('no raster')),
        onError: (error, _) => reported = error,
      );
      final undrawable = await support.undrawable();
      expect(reported, isA<StateError>());
      expect(undrawable, containsAll(['🫫', '👋🏻', '🥰']));
      expect(undrawable, isNot(contains('😀')));
      expect(undrawable, isNot(contains('👋')));
      expect(store.writes, 0);
    });

    test('a failed probe is tried again on the next ask', () async {
      var fail = true;
      final support = EmojiSupport(
        store: store,
        environment: 'os1',
        probe: (emoji) async {
          if (fail) throw StateError('no raster');
          return probe(emoji);
        },
      );
      expect(await support.undrawable(), contains('🥰'));
      expect(support.settled, isFalse);
      fail = false;
      expect(await support.undrawable(), {'🫫', '👋🏿'});
      expect(support.settled, isTrue);
      expect(store.writes, 1);
    });

    test('a probe past the deadline answers with the fallback, then caches '
        'and tells listeners when it lands', () async {
      final answer = Completer<List<bool>>();
      final support = EmojiSupport(
        store: store,
        environment: 'os1',
        deadline: Duration.zero,
        probe: (emoji) {
          probed.add(emoji);
          return answer.future;
        },
      );
      var told = 0;
      support.addListener(() => told++);

      expect(await support.undrawable(), contains('🥰'));
      expect(support.settled, isFalse);

      answer.complete([for (final e in probed.single) e != '🫫']);
      await pumpEventQueue();

      expect(told, 1);
      expect(await support.undrawable(), {'🫫'});
      expect(
        jsonDecode(store.values['emoji.undrawable']!),
        containsPair('emoji', ['🫫']),
      );
      expect(probed, hasLength(1));
    });

    test('a cache that cannot be saved still keeps the answer', () async {
      store.failWrites = true;
      Object? reported;
      final support = EmojiSupport(
        store: store,
        environment: 'os1',
        probe: probe,
        onError: (error, _) => reported = error,
      );

      expect(await support.undrawable(), {'🫫', '👋🏿'});
      expect(support.settled, isTrue);
      expect(reported, isA<StateError>());
      expect(probed, hasLength(1));
    });

    test('a probe answering the wrong count falls back', () async {
      final support = EmojiSupport(
        store: store,
        environment: 'os1',
        probe: (_) async => [true],
      );
      expect(await support.undrawable(), contains('🫫'));
      expect(store.writes, 0);
    });

    test('a corrupt cache probes again', () async {
      store.values['emoji.undrawable'] = 'not json';
      await EmojiSupport(
        store: store,
        environment: 'os1',
        probe: probe,
      ).undrawable();
      expect(probed, hasLength(1));
      expect(
        jsonDecode(store.values['emoji.undrawable']!),
        containsPair('emoji', ['🫫', '👋🏿']),
      );
    });
  });

  testWidgets('the probe runs while something animates', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: CircularProgressIndicator())),
    );
    final result = await tester.runAsync(() => probeDrawable(['😀', '👋🏽']));
    expect(result, hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  group('oneGlyph', () {
    test('accepts widths within 8% of the reference emoji', () {
      expect(oneGlyph(40, 40), isTrue);
      expect(oneGlyph(43, 40), isTrue);
      expect(oneGlyph(37, 40), isTrue);
    });

    test('rejects a sequence that fell apart or a narrow box', () {
      expect(oneGlyph(80, 40), isFalse);
      expect(oneGlyph(20, 40), isFalse);
    });
  });

  group('sameInkedCell', () {
    const width = 4;
    ByteData image(Map<(int, int), List<int>> pixels) {
      final data = ByteData(width * width * 4);
      for (final MapEntry(key: (x, y), value: rgba) in pixels.entries) {
        for (var c = 0; c < 4; c++) {
          data.setUint8((y * width + x) * 4 + c, rgba[c]);
        }
      }
      return data;
    }

    bool same(ByteData pixels, {int top = 0}) =>
        sameInkedCell(pixels, width, left: 0, otherLeft: 2, top: top, size: 2);

    test('a colored glyph drawn the same in both text colors passes', () {
      expect(
        same(
          image({
            (1, 1): [200, 120, 10, 255],
            (3, 1): [200, 120, 10, 255],
          }),
        ),
        isTrue,
      );
    });

    test('a box that took the text color fails', () {
      expect(
        same(
          image({
            (1, 1): [255, 0, 0, 255],
            (3, 1): [0, 0, 255, 255],
          }),
        ),
        isFalse,
      );
    });

    test('an empty cell fails', () {
      expect(same(image({})), isFalse);
    });

    test('only looks inside its cells', () {
      final pixels = image({
        (1, 1): [9, 9, 9, 255],
        (3, 1): [9, 9, 9, 255],
        (1, 3): [255, 0, 0, 255],
        (3, 3): [0, 0, 255, 255],
      });
      expect(same(pixels), isTrue);
      expect(same(pixels, top: 2), isFalse);
    });
  });
}
