import '../../../core/calls/models/call_kind.dart';

bool proximityScreenOffWanted({
  required CallKind kind,
  required bool speakerOn,
  required bool finished,
}) => kind == CallKind.voice && !speakerOn && !finished;
