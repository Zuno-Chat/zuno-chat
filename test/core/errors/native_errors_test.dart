import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/errors/native_caught_error.dart';
import 'package:zuno/core/errors/native_errors.dart';

import '../../helpers/native_method_calls.dart';
import '../../helpers/recording_sentry.dart';

void main() {
  final transport = useRecordingSentry();

  void nativeHolds(List<Object?> entries) =>
      recordMethodChannel(errorsChannel.name, reply: (_) => entries);

  test('a native caught error is reported under its native label', () async {
    nativeHolds([
      {
        'kind': 'caught',
        'label': 'share import',
        'type': 'java.lang.IllegalStateException',
        'message': 'no stream',
        'stack': 'at A.b(A.kt:1)',
      },
    ]);

    await drainNativeErrors();
    await pumpEventQueue();

    final event = transport.sentEvent;
    expect(event.tags?['caught'], 'native: share import');
    expect(
      (event.throwable as NativeCaughtError).type,
      'java.lang.IllegalStateException',
    );
  });

  test(
    'an iOS caught error is labelled with the process that caught it',
    () async {
      nativeHolds([
        {
          'kind': 'caught',
          'label': 'nse store open',
          'process': 'nse',
          'type': 'Foundation.CocoaError',
          'message': 'The file could not be opened.',
          'domain': 'NSCocoaErrorDomain',
          'code': 260,
        },
      ]);

      await drainNativeErrors();
      await pumpEventQueue();

      expect(transport.sentEvent.tags?['caught'], 'native nse: nse store open');
    },
  );

  test('a MetricKit summary is reported as a crash', () async {
    nativeHolds([
      {'kind': 'crash', 'summary': 'crash exception=1 signal=11'},
    ]);

    await drainNativeErrors();
    await pumpEventQueue();

    expect(
      transport.sentEvent.throwable,
      isA<IosDiagnostic>().having(
        (d) => d.summary,
        'summary',
        'crash exception=1 signal=11',
      ),
    );
  });

  test(
    'a native network failure and an unreadable entry are dropped',
    () async {
      nativeHolds([
        {
          'kind': 'caught',
          'label': 'nse fetch',
          'type': 'Foundation.URLError',
          'message': 'offline',
          'domain': 'NSURLErrorDomain',
          'code': -1009,
        },
        'not a map',
        {'kind': 'unknown'},
        {'kind': 'caught', 'label': 4},
      ]);

      await drainNativeErrors();
      await pumpEventQueue();

      expect(transport.events, isEmpty);
    },
  );

  test('a wrongly typed field does not stop the entries after it', () async {
    nativeHolds([
      {'kind': 'caught', 'label': 'first', 'type': 7, 'code': 'x'},
      {'kind': 'caught', 'label': 'second', 'type': 'java.lang.Error'},
    ]);

    await drainNativeErrors();
    await pumpEventQueue();

    expect(transport.events.map((e) => e.tags?['caught']), [
      'native: first',
      'native: second',
    ]);
  });

  test('without the native side, nothing happens', () async {
    await expectLater(drainNativeErrors(), completes);
    expect(transport.events, isEmpty);
  });
}
