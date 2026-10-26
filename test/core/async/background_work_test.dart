import 'dart:async';
import 'dart:isolate';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/async/background_work.dart';

import '../../helpers/platform_capabilities.dart';

void main() {
  test('the app runs background work in its own isolate', () async {
    final ranIn = await runInIsolate(
      () => Isolate.current.debugName,
      debugName: 'blurhash',
    );

    expect(ranIn, 'blurhash');
  });

  test('a release build runs it under the device log floor and hands back '
      'the result', () async {
    final result = await runInIsolate(
      () => 21 * 2,
      release: true,
      capabilities: iosCapabilities,
    );

    expect(result, 42);
  });

  test('the SDK hands its work and message through the same runner', () async {
    final ran = <String?>[];
    backgroundRunner = <R>(FutureOr<R> Function() work, {String? debugName}) {
      ran.add(debugName);
      return Future.sync(work);
    };

    final result = await computeInBackground(
      (int value) => value * 2,
      21,
      debugLabel: 'sdk work',
    );

    expect(result, 42);
    expect(ran, ['sdk work']);
  });

  test('tests run background work inline, so it finishes in fake time', () {
    fakeAsync((async) {
      int? result;
      runInBackground(() => 42).then((value) => result = value);

      async.flushMicrotasks();

      expect(result, 42);
    });
  });

  test('inline work that could not reach an isolate is refused, as the app '
      'would refuse it', () async {
    final port = ReceivePort();
    addTearDown(port.close);

    await expectLater(
      runInBackground(() => port.hashCode),
      throwsArgumentError,
    );
  });

  test('an inline result that could not come back from an isolate is '
      'refused', () async {
    final port = ReceivePort();
    addTearDown(port.close);

    await expectLater(runInBackground(() => port), throwsArgumentError);
  });
}
