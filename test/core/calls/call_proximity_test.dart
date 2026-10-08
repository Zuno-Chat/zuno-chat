import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/call_audio_route.dart';
import 'package:zuno/core/calls/call_proximity.dart';
import 'package:zuno/core/calls/models/call_kind.dart';

void main() {
  group('proximityScreenOffWanted', () {
    test('a voice call on the earpiece wants the screen off at the ear', () {
      expect(
        proximityScreenOffWanted(
          kind: CallKind.voice,
          audioRoute: CallAudioRoute.earpiece,
          screenOpen: true,
        ),
        isTrue,
      );
    });

    test('a video call keeps the screen on: the user is looking at it', () {
      expect(
        proximityScreenOffWanted(
          kind: CallKind.video,
          audioRoute: CallAudioRoute.earpiece,
          screenOpen: true,
        ),
        isFalse,
      );
    });

    test('speakerphone means the phone is not at the ear', () {
      expect(
        proximityScreenOffWanted(
          kind: CallKind.voice,
          audioRoute: CallAudioRoute.speaker,
          screenOpen: true,
        ),
        isFalse,
      );
    });

    test('a headset means the phone is not at the ear', () {
      for (final headset in [
        CallAudioRoute.bluetooth,
        CallAudioRoute.wiredHeadset,
      ]) {
        expect(
          proximityScreenOffWanted(
            kind: CallKind.voice,
            audioRoute: headset,
            screenOpen: true,
          ),
          isFalse,
          reason: headset.name,
        );
      }
    });

    test('a minimized call leaves the screen on: the user is using it', () {
      expect(
        proximityScreenOffWanted(
          kind: CallKind.voice,
          audioRoute: CallAudioRoute.earpiece,
          screenOpen: false,
        ),
        isFalse,
      );
    });
  });
}
