import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/errors/best_effort.dart';

import '../../helpers/recording_sentry.dart';

void main() {
  final transport = useRecordingSentry();

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

  test('a failing request is reported under its label', () async {
    await runBestEffort(
      () => throw StateError('no timeline'),
      label: 'mark read',
    );
    await pumpEventQueue();

    expect(transport.sentEvent.tags?['caught'], 'mark read');
  });

  test('a missing request is nothing to do', () async {
    expect(await runBestEffort(null, label: 'dispose camera'), isTrue);
  });
}
