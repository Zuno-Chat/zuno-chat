import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/platform/app_platform.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

const _networkChannel = EventChannel('zuno/network');

TestDefaultBinaryMessenger? _testMessenger() {
  if (BindingBase.debugBindingType() == null) return null;
  final messenger = ServicesBinding.instance.defaultBinaryMessenger;
  return messenger is TestDefaultBinaryMessenger ? messenger : null;
}

void _resetAmbientCapabilities() =>
    ambientCapabilities = capabilitiesFor(currentAppPlatform);

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    _resetAmbientCapabilities();
    _testMessenger()?.setMockStreamHandler(
      _networkChannel,
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
  });

  tearDown(_resetAmbientCapabilities);

  await testMain();
}
