import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:zuno/core/errors/feedback.dart';

const _dsn = 'https://key@o0.ingest.sentry.io/1';

class _RecordingTransport implements Transport {
  final bool accepts;
  final envelopes = <SentryEnvelope>[];

  _RecordingTransport({this.accepts = true});

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    envelopes.add(envelope);
    return accepts ? SentryId.newId() : SentryId.empty();
  }

  SentryEvent get sentEvent => envelopes.single.items
      .map((item) => item.originalObject)
      .whereType<SentryEvent>()
      .single;
}

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

  test('feedback is unavailable in a test build, which has no DSN', () {
    expect(feedbackAvailable, isFalse);
  });

  test('sends the message as a feedback event', () async {
    final transport = _RecordingTransport();

    await sendFeedback('Calls drop on wifi', dsn: _dsn, transport: transport);

    final event = transport.sentEvent;
    expect(event.type, 'feedback');
    expect(event.contexts.feedback?.message, 'Calls drop on wifi');
  });

  test('redacts identifiers and tokens typed into the message', () async {
    final transport = _RecordingTransport();

    await sendFeedback(
      '@alice:zuno.chat cannot join !abc:zuno.chat access_token=secret',
      dsn: _dsn,
      transport: transport,
    );

    final message = transport.sentEvent.contexts.feedback?.message;
    expect(message, isNot(contains('alice')));
    expect(message, isNot(contains('abc:zuno.chat')));
    expect(message, isNot(contains('secret')));
  });

  test('attaches the app release and the OS version, and no user', () async {
    final transport = _RecordingTransport();

    await sendFeedback('Idea', dsn: _dsn, transport: transport);

    final event = transport.sentEvent;
    expect(event.release, 'im.zuno.chat@1.2.3+45');
    expect(event.tags?['os'], Platform.operatingSystemVersion);
    expect(event.user, isNull);
  });

  test('throws when Sentry does not accept the feedback', () async {
    final transport = _RecordingTransport(accepts: false);

    await expectLater(
      sendFeedback('Idea', dsn: _dsn, transport: transport),
      throwsA(isA<FeedbackNotSent>()),
    );
  });

  test('throws without sending when no DSN is compiled in', () async {
    final transport = _RecordingTransport();

    await expectLater(
      sendFeedback('Idea', dsn: '', transport: transport),
      throwsA(isA<FeedbackNotSent>()),
    );
    expect(transport.envelopes, isEmpty);
  });
}
