import '../async/claimed_switch.dart';
import '../errors/best_effort.dart';
import 'notifications/call_notification_service.dart';

class ShowOverLockscreen extends ClaimedSwitch {
  ShowOverLockscreen._();

  static final instance = ShowOverLockscreen._();

  Future<void> releaseUnclaimed() async {
    if (!claimed) await send(false);
  }

  @override
  Future<void> send(bool on) => runBestEffort(
    () => CallNotificationService.instance.setShowOverLockscreen(on),
    label: 'show over the lock screen',
  );
}
