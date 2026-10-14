import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/hardcoded_user_text.dart';

final plugin = ZunoLintsPlugin();

class ZunoLintsPlugin extends Plugin {
  @override
  String get name => 'zuno_lints';

  @override
  void register(PluginRegistry registry) {
    registry.registerWarningRule(HardcodedUserText());
  }
}
