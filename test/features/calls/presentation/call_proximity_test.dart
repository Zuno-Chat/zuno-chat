import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/features/calls/presentation/call_proximity.dart';

void main() {
  group('proximityScreenOffWanted', () {
    test('a voice call on the earpiece wants the screen off at the ear', () {
      expect(
        proximityScreenOffWanted(
          kind: CallKind.voice,
          speakerOn: false,
          finished: false,
        ),
        isTrue,
      );
    });

    test('a video call keeps the screen on: the user is looking at it', () {
      expect(
        proximityScreenOffWanted(
          kind: CallKind.video,
          speakerOn: false,
          finished: false,
        ),
        isFalse,
      );
    });

    test('speakerphone means the phone is not at the ear', () {
      expect(
        proximityScreenOffWanted(
          kind: CallKind.voice,
          speakerOn: true,
          finished: false,
        ),
        isFalse,
      );
    });

    test('a finished call releases the screen', () {
      expect(
        proximityScreenOffWanted(
          kind: CallKind.voice,
          speakerOn: false,
          finished: true,
        ),
        isFalse,
      );
    });
  });
}
