import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:zuno/core/errors/feedback.dart';

import '../../helpers/recording_sentry.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Zuno',
      packageName: 'im.zuno.chat',
      version: '1.2.3',
      buildNumber: '45',
      buildSignature: '',
    );
  });

  test('sends the message as a feedback event', () async {
    final transport = RecordingTransport();

    await sendFeedback(
      'Calls drop on wifi',
      dsn: testSentryDsn,
      transport: transport,
    );

    final event = transport.sentEvent;
    expect(event.type, 'feedback');
    expect(event.contexts.feedback?.message, 'Calls drop on wifi');
  });

  test('redacts identifiers and tokens typed into the message', () async {
    final transport = RecordingTransport();

    await sendFeedback(
      '@alice:zuno.chat cannot join !abc:zuno.chat access_token=secret',
      dsn: testSentryDsn,
      transport: transport,
    );

    expect(
      transport.sentEvent.contexts.feedback?.message,
      '@[redacted] cannot join ![redacted] access_token=[redacted]',
    );
  });

  test('attaches the app release and the OS version, and no user', () async {
    final transport = RecordingTransport();

    await sendFeedback('Idea', dsn: testSentryDsn, transport: transport);

    final event = transport.sentEvent;
    expect(event.release, 'im.zuno.chat@1.2.3+45');
    expect(event.tags?['os'], Platform.operatingSystemVersion);
    expect(event.user, isNull);
  });

  test('throws when Sentry does not accept the feedback', () async {
    final transport = RecordingTransport(accepts: false);

    await expectLater(
      sendFeedback('Idea', dsn: testSentryDsn, transport: transport),
      throwsA(isA<FeedbackNotSent>()),
    );
  });

  test('throws without sending when no DSN is compiled in', () async {
    final transport = RecordingTransport();

    await expectLater(
      sendFeedback('Idea', dsn: '', transport: transport),
      throwsA(isA<FeedbackNotSent>()),
    );
    expect(transport.envelopes, isEmpty);
  });
}
