import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/files/unique_name.dart';

void main() {
  test('is 32 lowercase hex characters', () {
    expect(uniqueName(), matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  test('never repeats, even under a frozen clock', () {
    final names = withClock(
      Clock.fixed(DateTime(2031)),
      () => {for (var i = 0; i < 1000; i++) uniqueName()},
    );

    expect(names, hasLength(1000));
  });
}
