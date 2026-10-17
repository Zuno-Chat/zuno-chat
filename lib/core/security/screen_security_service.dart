import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../errors/caught_errors.dart';
import '../platform/platform_capabilities.dart';
import 'privacy_channel.dart';

class ScreenSecurityService {
  @visibleForTesting
  ScreenSecurityService({PlatformCapabilities? capabilities})
    : _injectedCapabilities = capabilities;
  static final instance = ScreenSecurityService();

  final PlatformCapabilities? _injectedCapabilities;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  bool _preferred = true;
  late final _secretScreens = _Holds(() {
    unawaited(_applyScreenshots());
    unawaited(_applyOverlays());
  });
  late final _signInScreens = _Holds(() => unawaited(_applyAccessibility()));

  Future<void> start({required bool preventScreenshots}) async {
    _preferred = preventScreenshots;
    await Future.wait([_applyScreenshots(), _applyAccessibility()]);
  }

  Future<void> followPreference(bool preventScreenshots) {
    _preferred = preventScreenshots;
    return _applyScreenshots();
  }

  VoidCallback protect() => _secretScreens.take();

  VoidCallback allowAccessibilityServices() => _signInScreens.take();

  Future<void> _applyScreenshots() => _send(
    'setPreventScreenshots',
    enabled: _preferred || _secretScreens.any,
    supported: _capabilities.screenSecurity,
  );

  Future<void> _applyOverlays() => _send(
    'setHideOverlays',
    enabled: _secretScreens.any,
    supported: _capabilities.overlayHiding,
  );

  Future<void> _applyAccessibility() => _send(
    'setAccessibilitySensitive',
    enabled: !_signInScreens.any,
    supported: _capabilities.accessibilitySensitivity,
  );

  Future<void> _send(
    String method, {
    required bool enabled,
    required bool supported,
  }) async {
    if (!supported) return;
    try {
      await privacyChannel.invokeMethod(method, {'enabled': enabled});
    } on MissingPluginException catch (e, s) {
      reportCaught('screen security $method', e, s);
    }
  }
}

class _Holds {
  _Holds(this._changed);

  final VoidCallback _changed;
  int _count = 0;

  bool get any => _count > 0;

  VoidCallback take() {
    if (_count++ == 0) _changed();
    var released = false;
    return () {
      if (released) return;
      released = true;
      if (--_count == 0) _changed();
    };
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

mixin AccessibilityServicesAllowed<T extends StatefulWidget> on State<T> {
  late final VoidCallback _releaseAccessibility;

  @override
  void initState() {
    super.initState();
    _releaseAccessibility = ScreenSecurityService.instance
        .allowAccessibilityServices();
  }

  @override
  void dispose() {
    _releaseAccessibility();
    super.dispose();
  }
}
