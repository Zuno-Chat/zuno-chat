import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const permissionDenied = 0;
const permissionGranted = 1;
const permissionPermanentlyDenied = 4;

class FakePermissions {
  int _onCheck = permissionGranted;
  final _checkedOf = <int, int>{};
  int onRequest = permissionGranted;
  final onRequestOf = <int, int>{};
  Completer<void>? checkGate;
  Completer<void>? requestGate;
  bool requestThrows = false;
  Object? error;
  final calls = <String>[];

  int get onCheck => _onCheck;

  set onCheck(int status) {
    _onCheck = status;
    _checkedOf.clear();
  }

  int get requests => calls.where((c) => c == 'requestPermissions').length;

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call.method);
    final error = this.error;
    if (error != null) throw error;
    switch (call.method) {
      case 'requestPermissions':
        await requestGate?.future;
        if (requestThrows) throw PlatformException(code: 'already-running');
        final answers = {
          for (final permission in (call.arguments as List).cast<int>())
            permission: onRequestOf[permission] ?? onRequest,
        };
        _checkedOf.addAll(answers);
        return answers;
      case 'checkPermissionStatus':
        await checkGate?.future;
        return _checkedOf[call.arguments] ?? _onCheck;
      case 'openAppSettings':
        return true;
    }
    return null;
  }
}

FakePermissions installFakePermissions({
  int onCheck = permissionGranted,
  int onRequest = permissionGranted,
}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final permissions = FakePermissions()
    ..onCheck = onCheck
    ..onRequest = onRequest;
  messenger.setMockMethodCallHandler(channel, permissions._handle);
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return permissions;
}
