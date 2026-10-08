import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/platform/incoming_call_presenter.dart';
import 'package:zuno/core/calls/platform/system_ring.dart';
import 'package:zuno/core/calls/serial_lock.dart';
import 'package:zuno/core/platform/app_platform.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

const _networkChannel = EventChannel('zuno/network');
const _liveLocationChannel = MethodChannel('zuno/live_location');
const _liveLocationFixes = EventChannel('zuno/live_location/fixes');

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
    final messenger = _testMessenger();
    messenger?.setMockStreamHandler(
      _networkChannel,
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    messenger?.setMockStreamHandler(
      _liveLocationFixes,
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    messenger?.setMockMethodCallHandler(
      _liveLocationChannel,
      (_) async => null,
    );
  });

  tearDown(_resetAmbientCapabilities);
  tearDown(SystemRing.instance.reset);
  tearDown(KeyedSerialLock.forgetAllForTest);
  tearDown(RememberingIncomingCallPresenter.forgetForTest);

  await testMain();
}
