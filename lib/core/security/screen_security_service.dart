import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../errors/caught_errors.dart';
import '../platform/platform_capabilities.dart';

const _channel = MethodChannel('zuno/calls');

class ScreenSecurityService {
  @visibleForTesting
  ScreenSecurityService({PlatformCapabilities? capabilities})
    : _injectedCapabilities = capabilities;
  static final instance = ScreenSecurityService();

  final PlatformCapabilities? _injectedCapabilities;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  bool _preferred = true;
  int _protectedScreens = 0;

  Future<void> followPreference(bool preventScreenshots) {
    _preferred = preventScreenshots;
    return _apply();
  }

  VoidCallback protect() {
    if (_protectedScreens++ == 0) unawaited(_apply());
    var released = false;
    return () {
      if (released) return;
      released = true;
      if (--_protectedScreens == 0) unawaited(_apply());
    };
  }

  Future<void> _apply() async {
    if (!_capabilities.screenSecurity) return;
    try {
      await _channel.invokeMethod('setPreventScreenshots', {
        'enabled': _preferred || _protectedScreens > 0,
      });
    } on MissingPluginException catch (e, s) {
      reportCaught('set screenshot prevention', e, s);
    }
  }
}

mixin ScreenProtected<T extends StatefulWidget> on State<T> {
  late final VoidCallback _releaseScreen;

  @override
  void initState() {
    super.initState();
    _releaseScreen = ScreenSecurityService.instance.protect();
  }

  @override
  void dispose() {
    _releaseScreen();
    super.dispose();
  }
}
