import '../../../core/l10n/l10n.dart';
import '../../../core/notifications/unified_push_delivery_provider.dart'
    show UnifiedPushStatus;
import '../../../core/push/unified_push_distributor_names.dart';

enum UnifiedPushStatusAction { none, register, retry }

UnifiedPushStatusAction unifiedPushStatusAction(
  UnifiedPushStatus status, {
  bool removed = false,
}) {
  switch (status) {
    case UnifiedPushStatus.idle:
      return removed
          ? UnifiedPushStatusAction.register
          : UnifiedPushStatusAction.none;
    case UnifiedPushStatus.findingDistributor:
    case UnifiedPushStatus.noDistributorFound:
    case UnifiedPushStatus.registering:
    case UnifiedPushStatus.postingPusher:
      return UnifiedPushStatusAction.none;
    case UnifiedPushStatus.distributorSelected:
      return UnifiedPushStatusAction.register;
    case UnifiedPushStatus.registrationFailed:
    case UnifiedPushStatus.pusherFailed:
      return UnifiedPushStatusAction.retry;
    case UnifiedPushStatus.ready:
      return UnifiedPushStatusAction.none;
  }
}

String unifiedPushStatusLabel(AppLocalizations l10n, UnifiedPushStatus status) {
  switch (status) {
    case UnifiedPushStatus.idle:
    case UnifiedPushStatus.noDistributorFound:
      return l10n.pushInactive;
    case UnifiedPushStatus.findingDistributor:
      return l10n.pushSearching;
    case UnifiedPushStatus.distributorSelected:
      return l10n.pushNotRegisteredYet;
    case UnifiedPushStatus.registering:
      return l10n.pushRegistering;
    case UnifiedPushStatus.postingPusher:
      return l10n.pushFinishingRegistration;
    case UnifiedPushStatus.ready:
      return l10n.pushActive;
    case UnifiedPushStatus.registrationFailed:
      return l10n.pushDistributorRefusedRegistration;
    case UnifiedPushStatus.pusherFailed:
      return l10n.pushCouldNotFinishRegistration;
  }
}

String unifiedPushDistributorLabel(
  AppLocalizations l10n, {
  required UnifiedPushStatus status,
  required String? distributor,
}) {
  if (status == UnifiedPushStatus.findingDistributor) {
    return l10n.pushSearching;
  }
  if (distributor != null && distributor.isNotEmpty) {
    return unifiedPushDistributorDisplayName(distributor);
  }
  if (status == UnifiedPushStatus.noDistributorFound) {
    return l10n.pushNoDistributorInstalled;
  }
  return distributor == null ? l10n.commonChecking : l10n.pushNoneSelected;
}
