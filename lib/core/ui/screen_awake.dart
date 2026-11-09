import 'package:wakelock_plus/wakelock_plus.dart';

import '../async/claimed_switch.dart';
import '../errors/best_effort.dart';

class ScreenAwake extends ClaimedSwitch {
  ScreenAwake._();

  static final instance = ScreenAwake._();

  @override
  Future<void> send(bool on) => runBestEffort(
    () => WakelockPlus.toggle(enable: on),
    label: on ? 'keep the screen on' : 'let the screen sleep',
  );
}
