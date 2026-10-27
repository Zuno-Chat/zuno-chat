import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/redactions.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  final room = buildTestRoom(buildTestClient());

  Event redaction({String? topLevel, String? inContent}) => Event(
    eventId: r'$r',
    type: EventTypes.Redaction,
    senderId: '@a:example.org',
    originServerTs: DateTime(2026),
    content: {'redacts': ?inContent},
    redacts: topLevel,
    room: room,
  );

  test('reads the target from the top level, as older rooms send it', () {
    expect(redactionTarget(redaction(topLevel: r'$gone')), r'$gone');
  });

  test('reads the target from the content, as room version 11 sends it', () {
    expect(redactionTarget(redaction(inContent: r'$gone')), r'$gone');
  });

  test('has no target when neither carries one', () {
    expect(redactionTarget(redaction()), isNull);
  });
}
