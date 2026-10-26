import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/direct_background_work.dart';
import 'src/direct_clock_read.dart';
import 'src/direct_disk_access.dart';
import 'src/hardcoded_user_text.dart';
import 'src/real_time_wait.dart';

final plugin = ZunoLintsPlugin();

class ZunoLintsPlugin extends Plugin {
  @override
  String get name => 'zuno_lints';

  @override
  void register(PluginRegistry registry) {
    registry
      ..registerWarningRule(HardcodedUserText())
      ..registerWarningRule(DirectClockRead())
      ..registerWarningRule(DirectDiskAccess())
      ..registerWarningRule(DirectBackgroundWork())
      ..registerWarningRule(RealTimeWait());
  }
}
