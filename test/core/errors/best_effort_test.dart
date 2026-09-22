import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/errors/best_effort.dart';

void main() {
  test('a request that succeeds reports success', () async {
    var ran = false;
    final ok = await runBestEffort(() async {
      ran = true;
    }, label: 'test');

    expect(ran, isTrue);
    expect(ok, isTrue);
  });

  test('a failing request is swallowed and reported as a failure', () async {
    final ok = await runBestEffort(
      () async => throw Exception('http error response'),
      label: 'test',
    );

    expect(ok, isFalse);
  });

  test('a request that throws synchronously is swallowed too', () async {
    final ok = await runBestEffort(() {
      throw StateError('no timeline');
    }, label: 'test');

    expect(ok, isFalse);
  });
}
