import '../../l10n/l10n.dart';
import '../matrixrtc/active_room_call.dart';

enum CallFailure {
  connectionLost,
  didNotConnect,
  microphoneUnavailable,
  noPermissionToStart,
  callFull,
  onAnotherDevice;

  String message(AppLocalizations l10n) => switch (this) {
    connectionLost => l10n.callsFailureConnectionLost,
    didNotConnect => l10n.callsFailureDidNotConnect,
    microphoneUnavailable => l10n.callsFailureMicrophone,
    noPermissionToStart => l10n.callsFailureNoPermission,
    callFull => l10n.callsFailureCallFull(maxCallParticipants),
    onAnotherDevice => l10n.callsFailureOnAnotherDevice,
  };
}
