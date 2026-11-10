import '../../l10n/l10n.dart';

enum PushStatusAction { none, register, retry, fix }

String? pushStatusActionLabel(AppLocalizations l10n, PushStatusAction action) =>
    switch (action) {
      PushStatusAction.register => l10n.notificationsRegister,
      PushStatusAction.retry => l10n.commonRetry,
      PushStatusAction.none || PushStatusAction.fix => null,
    };
