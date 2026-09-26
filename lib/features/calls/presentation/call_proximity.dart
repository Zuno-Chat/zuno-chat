import '../../../core/calls/models/call_kind.dart';
import 'call_audio_route.dart';

bool proximityScreenOffWanted({
  required CallKind kind,
  required CallAudioRoute audioRoute,
  required bool finished,
}) =>
    kind == CallKind.voice &&
    audioRoute == CallAudioRoute.earpiece &&
    !finished;
