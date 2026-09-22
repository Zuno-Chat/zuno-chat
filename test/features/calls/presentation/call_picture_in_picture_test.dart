import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/models/call_engine_participant.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';
import 'package:zuno/features/calls/presentation/call_picture_in_picture.dart';

void main() {
  const local = CallEngineParticipant(
    id: VoipParticipantId(userId: 'local', deviceId: 'local'),
    isLocal: true,
    videoEnabled: true,
  );
  const remoteA = CallEngineParticipant(
    id: VoipParticipantId(userId: '@a:x', deviceId: 'A'),
    isLocal: false,
  );
  const remoteB = CallEngineParticipant(
    id: VoipParticipantId(userId: '@b:x', deviceId: 'B'),
    isLocal: false,
  );

  group('pictureInPictureRemote', () {
    test('picks the remote whose camera is on', () {
      final on = remoteA.copyWith(videoEnabled: true);
      expect(pictureInPictureRemote([local, on]), on);
    });

    test('ignores the local camera: only a remote video qualifies', () {
      expect(pictureInPictureRemote([local, remoteA]), isNull);
    });

    test('skips a camera-off remote in favour of a later one with video', () {
      final on = remoteB.copyWith(videoEnabled: true);
      expect(pictureInPictureRemote([local, remoteA, on]), on);
    });

    test('is null when nobody is in the call yet', () {
      expect(pictureInPictureRemote(const []), isNull);
    });
  });

  group('pictureInPictureAspect', () {
    test('uses the video frame size when known', () {
      expect(pictureInPictureAspect(640, 480), (width: 640, height: 480));
    });

    test('falls back to portrait 3:4 before the first frame arrives', () {
      expect(pictureInPictureAspect(0, 0), (width: 3, height: 4));
    });

    test('clamps a very wide frame to the widest ratio Android allows', () {
      expect(pictureInPictureAspect(1000, 100), (width: 239, height: 100));
    });

    test('clamps a very tall frame to the tallest ratio Android allows', () {
      expect(pictureInPictureAspect(100, 1000), (width: 100, height: 239));
    });
  });
}
