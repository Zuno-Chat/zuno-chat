import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:zuno/core/errors/caught_errors.dart';

const testSentryDsn = 'https://key@o0.ingest.sentry.io/1';

class RecordingTransport implements Transport {
  RecordingTransport({this.accepts = true});

  final bool accepts;
  final envelopes = <SentryEnvelope>[];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    envelopes.add(envelope);
    return accepts ? SentryId.newId() : SentryId.empty();
  }

  List<SentryEvent> get events => [
    for (final envelope in envelopes)
      ...envelope.items
          .map((item) => item.originalObject)
          .whereType<SentryEvent>(),
  ];

  SentryEvent get sentEvent => events.single;
}

Future<void> startRecordingSentry(RecordingTransport transport) =>
    Sentry.init((options) {
      options.dsn = testSentryDsn;
      options.transport = transport;
    });

RecordingTransport useRecordingSentry() {
  final transport = RecordingTransport();
  setUp(() async {
    forgetReportedLabels();
    transport.envelopes.clear();
    await startRecordingSentry(transport);
  });
  tearDown(() async {
    await Sentry.close();
    forgetReportedLabels();
  });
  return transport;
}
