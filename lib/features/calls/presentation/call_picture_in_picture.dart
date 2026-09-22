import '../../../core/calls/models/call_engine_participant.dart';

typedef PictureInPictureAspect = ({int width, int height});

const _maxAspectRatio = 2.39;
const _defaultAspect = (width: 3, height: 4);

CallEngineParticipant? pictureInPictureRemote(
  List<CallEngineParticipant> participants,
) => participants.where((p) => !p.isLocal && p.videoEnabled).firstOrNull;

PictureInPictureAspect pictureInPictureAspect(int videoWidth, int videoHeight) {
  if (videoWidth <= 0 || videoHeight <= 0) return _defaultAspect;
  final ratio = videoWidth / videoHeight;
  if (ratio > _maxAspectRatio) return (width: 239, height: 100);
  if (ratio < 1 / _maxAspectRatio) return (width: 100, height: 239);
  return (width: videoWidth, height: videoHeight);
}
