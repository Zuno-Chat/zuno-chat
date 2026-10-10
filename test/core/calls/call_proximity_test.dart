import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/call_audio_route.dart';
import 'package:zuno/core/calls/call_proximity.dart';
import 'package:zuno/core/calls/models/call_kind.dart';

void main() {
  group('proximityScreenOffWanted', () {
    const cases = {
      'a voice call on the earpiece wants the screen off at the ear': (
        kind: CallKind.voice,
        route: CallAudioRoute.earpiece,
        screenOpen: true,
        wanted: true,
      ),
      'a video call keeps the screen on: the user is looking at it': (
        kind: CallKind.video,
        route: CallAudioRoute.earpiece,
        screenOpen: true,
        wanted: false,
      ),
      'speakerphone means the phone is not at the ear': (
        kind: CallKind.voice,
        route: CallAudioRoute.speaker,
        screenOpen: true,
        wanted: false,
      ),
      'a bluetooth headset means the phone is not at the ear': (
        kind: CallKind.voice,
        route: CallAudioRoute.bluetooth,
        screenOpen: true,
        wanted: false,
      ),
      'a wired headset means the phone is not at the ear': (
        kind: CallKind.voice,
        route: CallAudioRoute.wiredHeadset,
        screenOpen: true,
        wanted: false,
      ),
      'a minimized call leaves the screen on: the user is using it': (
        kind: CallKind.voice,
        route: CallAudioRoute.earpiece,
        screenOpen: false,
        wanted: false,
      ),
    };

    for (final MapEntry(key: name, value: call) in cases.entries) {
      test(name, () {
        expect(
          proximityScreenOffWanted(
            kind: call.kind,
            audioRoute: call.route,
            screenOpen: call.screenOpen,
          ),
          call.wanted,
        );
      });
    }
  });
}
