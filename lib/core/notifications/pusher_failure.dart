import '../l10n/l10n.dart';

sealed class PusherFailure {
  const PusherFailure();

  String message(AppLocalizations l10n) => switch (this) {
    PusherServerMissing() => l10n.pushNoServerYet,
    PusherPostFailed(:final detail) => detail,
    PusherRemoveFailed(:final detail) => l10n.pushCouldNotRemoveRegistration(
      detail,
    ),
  };
}

final class PusherServerMissing extends PusherFailure {
  const PusherServerMissing();
}

final class PusherPostFailed extends PusherFailure {
  const PusherPostFailed(this.detail);

  final String detail;
}

final class PusherRemoveFailed extends PusherFailure {
  const PusherRemoveFailed(this.detail);

  final String detail;
}
