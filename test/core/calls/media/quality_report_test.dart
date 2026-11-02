import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/media/quality_report.dart';
import 'package:zuno/core/calls/models/call_quality.dart';

void main() {
  test('round-trips every tier', () {
    for (final quality in CallQuality.values) {
      expect(decodeQualityReport(encodeQualityReport(quality)), quality);
    }
  });

  test('writes the tier under one key', () {
    expect(encodeQualityReport(CallQuality.degraded), '{"quality":"degraded"}');
  });

  test('rejects malformed JSON, a missing field and an unknown tier', () {
    expect(decodeQualityReport('not json'), isNull);
    expect(decodeQualityReport('[]'), isNull);
    expect(decodeQualityReport('{}'), isNull);
    expect(decodeQualityReport('{"quality":3}'), isNull);
    expect(decodeQualityReport('{"quality":"terrible"}'), isNull);
  });

  test('ignores extra fields', () {
    expect(
      decodeQualityReport('{"quality":"poor","since":12}'),
      CallQuality.poor,
    );
  });
}
