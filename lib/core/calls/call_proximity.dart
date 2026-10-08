import 'call_audio_route.dart';
import 'models/call_kind.dart';

bool proximityScreenOffWanted({
  required CallKind kind,
  required CallAudioRoute audioRoute,
  required bool screenOpen,
}) =>
    kind == CallKind.voice &&
    audioRoute == CallAudioRoute.earpiece &&
    screenOpen;
