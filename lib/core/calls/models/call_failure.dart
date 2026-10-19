import '../../l10n/l10n.dart';

sealed class CallFailure {
  const CallFailure();

  String message(AppLocalizations l10n) => switch (this) {
    CallConnectionLost() => l10n.callsFailureConnectionLost,
    CallDidNotConnect() => l10n.callsFailureDidNotConnect,
    CallMicrophoneUnavailable() => l10n.callsFailureMicrophone,
    CallNoPermissionToStart() => l10n.callsFailureNoPermission,
    CallFull(:final maxParticipants) => l10n.callsFailureCallFull(
      maxParticipants,
    ),
    CallOnAnotherDevice() => l10n.callsFailureOnAnotherDevice,
  };
}

final class CallConnectionLost extends CallFailure {
  const CallConnectionLost();
}

final class CallDidNotConnect extends CallFailure {
  const CallDidNotConnect();
}

final class CallMicrophoneUnavailable extends CallFailure {
  const CallMicrophoneUnavailable();
}

final class CallNoPermissionToStart extends CallFailure {
  const CallNoPermissionToStart();
}

final class CallFull extends CallFailure {
  const CallFull(this.maxParticipants);

  final int maxParticipants;
}

final class CallOnAnotherDevice extends CallFailure {
  const CallOnAnotherDevice();
}
