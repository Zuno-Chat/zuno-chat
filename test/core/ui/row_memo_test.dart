import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/row_memo.dart';

void main() {
  test('equal data returns the identical widget without building', () {
    final memo = RowMemo<String>();
    var builds = 0;
    Widget build() {
      builds++;
      return const SizedBox();
    }

    final first = memo.obtain('a', 'same', () => SizedBox(key: UniqueKey()));
    final second = memo.obtain('a', 'same', build);

    expect(identical(first, second), isTrue);
    expect(builds, 0);
  });

  test('changed data builds a new widget', () {
    final memo = RowMemo<String>();

    final first = memo.obtain('a', 'one', () => SizedBox(key: UniqueKey()));
    final second = memo.obtain('a', 'two', () => SizedBox(key: UniqueKey()));

    expect(identical(first, second), isFalse);
  });

  test('ids are independent', () {
    final memo = RowMemo<String>();

    final a = memo.obtain('a', 'same', () => SizedBox(key: UniqueKey()));
    final b = memo.obtain('b', 'same', () => SizedBox(key: UniqueKey()));

    expect(identical(a, b), isFalse);
  });

  test('unlisted ids are dropped, so they build again', () {
    final memo = RowMemo<String>();
    final first = memo.obtain('a', 'same', () => SizedBox(key: UniqueKey()));

    memo.retainOnly(['b']);
    final again = memo.obtain('a', 'same', () => SizedBox(key: UniqueKey()));

    expect(identical(first, again), isFalse);
  });

  test('capacity evicts the least recently used entry', () {
    final memo = RowMemo<int>(capacity: 2);
    final a = memo.obtain('a', 1, () => Container());
    memo.obtain('b', 1, () => Container());
    expect(identical(memo.obtain('a', 1, () => Container()), a), isTrue);
    memo.obtain('c', 1, () => Container());
    expect(identical(memo.obtain('a', 1, () => Container()), a), isTrue);
    var rebuilt = false;
    memo.obtain('b', 1, () {
      rebuilt = true;
      return Container();
    });
    expect(rebuilt, isTrue);
  });

  test('clear forgets every entry', () {
    final memo = RowMemo<int>();
    final a = memo.obtain('a', 1, () => Container());
    memo.clear();
    expect(identical(memo.obtain('a', 1, () => Container()), a), isFalse);
  });
}
