import '../../../core/notifications/unified_push_delivery_provider.dart'
    show UnifiedPushStatus;
import '../../../core/push/unified_push_distributor_names.dart';

enum UnifiedPushStatusAction { none, register, retry, open }

UnifiedPushStatusAction unifiedPushStatusAction(UnifiedPushStatus status) {
  switch (status) {
    case UnifiedPushStatus.idle:
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
      return UnifiedPushStatusAction.open;
  }
}

String unifiedPushStatusLabel(UnifiedPushStatus status) {
  switch (status) {
    case UnifiedPushStatus.idle:
    case UnifiedPushStatus.noDistributorFound:
      return 'Inactive';
    case UnifiedPushStatus.findingDistributor:
      return 'Searching…';
    case UnifiedPushStatus.distributorSelected:
      return 'Not registered yet';
    case UnifiedPushStatus.registering:
      return 'Registering…';
    case UnifiedPushStatus.postingPusher:
      return 'Registering with the server…';
    case UnifiedPushStatus.ready:
      return 'Active. Receiving notifications.';
    case UnifiedPushStatus.registrationFailed:
      return 'The distributor refused the registration';
    case UnifiedPushStatus.pusherFailed:
      return 'The server rejected the registration';
  }
}

String unifiedPushDistributorLabel({
  required UnifiedPushStatus status,
  required String? distributor,
}) {
  if (status == UnifiedPushStatus.findingDistributor) return 'Searching…';
  if (distributor != null && distributor.isNotEmpty) {
    return unifiedPushDistributorDisplayName(distributor);
  }
  if (status == UnifiedPushStatus.noDistributorFound) {
    return 'None installed. Install one, such as ntfy, then refresh.';
  }
  return distributor == null ? 'Checking…' : 'None selected';
}
