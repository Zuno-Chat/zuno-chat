import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/matrix/vodozemac_init.dart';

void main() {
  setUp(resetVodozemacInitForTest);

  test('initializes once, however many clients an isolate builds', () async {
    var calls = 0;
    Future<void> init() async => calls++;

    await ensureVodozemacInitialized(init: init);
    await ensureVodozemacInitialized(init: init);
    await ensureVodozemacInitialized(init: init);

    expect(calls, 1);
  });

  test('concurrent callers share one initialization', () async {
    var calls = 0;
    final held = Completer<void>();
    Future<void> init() async {
      calls++;
      await held.future;
    }

    final both = Future.wait([
      ensureVodozemacInitialized(init: init),
      ensureVodozemacInitialized(init: init),
    ]);
    held.complete();
    await both;

    expect(calls, 1);
  });

  test('reports a failed initialization instead of swallowing it', () async {
    Future<void> init() async => throw StateError('no native library');

    await expectLater(
      ensureVodozemacInitialized(init: init),
      throwsA(isA<StateError>()),
    );
  });

  test('retries after a failure rather than caching it', () async {
    var calls = 0;
    Future<void> init() async {
      calls++;
      if (calls == 1) throw StateError('no native library');
    }

    await expectLater(
      ensureVodozemacInitialized(init: init),
      throwsA(isA<StateError>()),
    );
    await ensureVodozemacInitialized(init: init);

    expect(calls, 2);
    await ensureVodozemacInitialized(init: init);
    expect(calls, 2);
  });

  test(
    'a synchronous throw leaves nothing cached for the next caller',
    () async {
      var calls = 0;
      Future<void> init() {
        calls++;
        if (calls == 1) throw StateError('no native library');
        return Future<void>.value();
      }

      await expectLater(
        ensureVodozemacInitialized(init: init),
        throwsA(isA<StateError>()),
      );
      await ensureVodozemacInitialized(init: init);

      expect(calls, 2);
    },
  );
}
