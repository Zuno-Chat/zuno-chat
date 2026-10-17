import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../errors/caught_errors.dart';
import '../platform/platform_capabilities.dart';
import 'privacy_channel.dart';

class ThirdPartyKeyboards {
  @visibleForTesting
  ThirdPartyKeyboards({PlatformCapabilities? capabilities})
    : _injectedCapabilities = capabilities;
  static final instance = ThirdPartyKeyboards();

  final PlatformCapabilities? _injectedCapabilities;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  Future<void> followIncognito(bool incognito) async {
    if (!_capabilities.thirdPartyKeyboardBlocking) return;
    try {
      await privacyChannel.invokeMethod('setThirdPartyKeyboards', {
        'allowed': !incognito,
      });
    } on MissingPluginException catch (e, s) {
      reportCaught('allow third-party keyboards', e, s);
    }
  }
}
