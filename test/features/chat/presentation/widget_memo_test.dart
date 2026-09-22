import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/features/chat/presentation/widget_memo.dart';

void main() {
  test('hands back the same instance for the same key', () {
    final memo = WidgetMemo(capacity: 4);
    var builds = 0;
    Widget build() {
      builds++;
      return const SizedBox();
    }

    final first = memo.obtain('a', build);
    final again = memo.obtain('a', build);

    expect(identical(first, again), isTrue);
    expect(builds, 1);
  });

  test('builds afresh for a different key', () {
    final memo = WidgetMemo(capacity: 4);

    final a = memo.obtain('a', () => const SizedBox());
    final b = memo.obtain(
      'b',
      () => const Text('b', textDirection: TextDirection.ltr),
    );

    expect(identical(a, b), isFalse);
  });

  test('evicts the least recently used entry beyond capacity', () {
    final memo = WidgetMemo(capacity: 2);
    final a = memo.obtain('a', () => const SizedBox());
    memo.obtain('b', () => const SizedBox());
    memo.obtain('a', () => const SizedBox());
    memo.obtain('c', () => const SizedBox());

    expect(identical(memo.obtain('a', () => const SizedBox()), a), isTrue);
    final b2 = memo.obtain('b', () => const SizedBox(width: 1));
    expect(b2, isA<SizedBox>().having((s) => s.width, 'width', 1));
  });
}
