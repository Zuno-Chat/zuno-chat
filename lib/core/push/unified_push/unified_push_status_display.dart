import '../../l10n/l10n.dart';
import 'unified_push_delivery_provider.dart' show UnifiedPushStatus;
import 'unified_push_distributor_names.dart';

enum UnifiedPushStatusAction { none, register, retry }

UnifiedPushStatusAction unifiedPushStatusAction(
  UnifiedPushStatus status, {
  bool removed = false,
}) => switch (status) {
  UnifiedPushStatus.idle =>
    removed ? UnifiedPushStatusAction.register : UnifiedPushStatusAction.none,
  UnifiedPushStatus.distributorSelected => UnifiedPushStatusAction.register,
  UnifiedPushStatus.registrationFailed ||
  UnifiedPushStatus.pusherFailed => UnifiedPushStatusAction.retry,
  UnifiedPushStatus.findingDistributor ||
  UnifiedPushStatus.noDistributorFound ||
  UnifiedPushStatus.registering ||
  UnifiedPushStatus.postingPusher ||
  UnifiedPushStatus.ready => UnifiedPushStatusAction.none,
};

bool unifiedPushStatusIsBusy(UnifiedPushStatus status) => switch (status) {
  UnifiedPushStatus.findingDistributor ||
  UnifiedPushStatus.registering ||
  UnifiedPushStatus.postingPusher => true,
  UnifiedPushStatus.idle ||
  UnifiedPushStatus.noDistributorFound ||
  UnifiedPushStatus.distributorSelected ||
  UnifiedPushStatus.ready ||
  UnifiedPushStatus.registrationFailed ||
  UnifiedPushStatus.pusherFailed => false,
};

String unifiedPushStatusLabel(
  AppLocalizations l10n,
  UnifiedPushStatus status,
) => switch (status) {
  UnifiedPushStatus.idle ||
  UnifiedPushStatus.noDistributorFound => l10n.pushInactive,
  UnifiedPushStatus.findingDistributor => l10n.pushSearching,
  UnifiedPushStatus.distributorSelected => l10n.pushNotRegisteredYet,
  UnifiedPushStatus.registering => l10n.pushRegistering,
  UnifiedPushStatus.postingPusher => l10n.pushFinishingRegistration,
  UnifiedPushStatus.ready => l10n.pushActive,
  UnifiedPushStatus.registrationFailed =>
    l10n.pushDistributorRefusedRegistration,
  UnifiedPushStatus.pusherFailed => l10n.pushCouldNotFinishRegistration,
};

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
