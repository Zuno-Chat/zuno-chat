import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:zuno/core/errors/caught_errors.dart';
import 'package:zuno/core/errors/crash_reporting.dart';

import '../../helpers/recording_sentry.dart';

void main() {
  final transport = useRecordingSentry();

  test('sends a handled error, grouped by its label and type', () async {
    await captureCaught(
      'save draft',
      StateError('no room'),
      StackTrace.current,
    );

    final event = transport.sentEvent;
    expect(event.throwable, isA<StateError>());
    expect(event.tags?['caught'], 'save draft');
    expect(event.fingerprint, ['save draft', 'StateError']);
  });

  test('sends a label only once per run', () async {
    await captureCaught('save draft', StateError('first'), null);
    await captureCaught('save draft', StateError('again'), null);
    await captureCaught('load draft', StateError('other'), null);

    expect(transport.events.map((e) => e.tags?['caught']), [
      'save draft',
      'load draft',
    ]);
  });

  test('never sends a network failure', () async {
    await captureCaught('sync', const SocketException('offline'), null);

    expect(transport.events, isEmpty);
  });

  test('sends nothing while reporting is off, and keeps the label', () async {
    await Sentry.close();
    await captureCaught('save draft', StateError('off'), null);

    await startRecordingSentry(transport);
    await captureCaught('save draft', StateError('on'), null);

    expect(transport.sentEvent.throwable.toString(), contains('on'));
  });

  test('a failing future is reported once and still fails', () async {
    await expectLater(
      reportFailureOf(Future<void>.error(StateError('x')), label: 'load list'),
      throwsStateError,
    );
    await pumpEventQueue();

    expect(transport.sentEvent.tags?['caught'], 'load list');
  });

  test('only the type of a sensitive error is sent', () async {
    reportCaughtType('find location', const FormatException('51.5,-0.12'));
    await pumpEventQueue();

    expect(transport.sentEvent.throwable.toString(), 'FormatException');
    expect(transport.sentEvent.fingerprint, [
      'find location',
      'FormatException',
    ]);
  });

  test('a sensitive network failure is still never sent', () async {
    reportCaughtType('find location', const SocketException('offline'));
    await pumpEventQueue();

    expect(transport.events, isEmpty);
  });

  test('an error caught while reporting starts waits for it', () async {
    await Sentry.close();
    final starting = Completer<void>();
    noteCrashReportingStart(starting.future);

    final sent = captureCaught('first push', StateError('cold'), null);
    await startRecordingSentry(transport);
    starting.complete();
    await sent;

    expect(transport.sentEvent.tags?['caught'], 'first push');
  });
}
