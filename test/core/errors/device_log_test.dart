import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/errors/device_log.dart';

import '../../helpers/platform_capabilities.dart';

Future<void> _logSecrets() async {
  debugPrint('secret before an await');
  await Future<void>.delayed(Duration.zero);
  Logs().i('Sending type m.key.verification.start: secret');
  Logs().wtf('secret at any level');
  await Future<void>.delayed(Duration.zero);
  debugPrint('secret after an await');
}

Future<List<String>> _printedBy({required bool release}) async {
  final printed = <String>[];
  await runZoned(
    () => runWithDeviceLogFloor(
      _logSecrets,
      release: release,
      capabilities: iosCapabilities,
      raiseNativeFloor: () {},
    ),
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, line) => printed.add(line),
    ),
  );
  return printed;
}

void main() {
  tearDown(Logs().outputEvents.clear);

  test('a release build prints nothing, from the app or the SDK', () async {
    expect(await _printedBy(release: true), isEmpty);
  });

  test('a debug or profile build keeps printing', () async {
    final printed = await _printedBy(release: false);

    expect(printed, contains('secret before an await'));
    expect(printed, contains('secret after an await'));
    expect(printed.where((line) => line.startsWith('[Matrix]')), hasLength(2));
  });

  test('a release build raises the native floor where there is one', () {
    var raised = 0;

    final result = runWithDeviceLogFloor(
      () => 'ran',
      release: true,
      capabilities: androidCapabilities,
      raiseNativeFloor: () => raised++,
    );

    expect(result, 'ran');
    expect(raised, 1);
  });

  test('iOS has no native floor to raise', () {
    var raised = 0;

    final result = runWithDeviceLogFloor(
      () => 'ran',
      release: true,
      capabilities: iosCapabilities,
      raiseNativeFloor: () => raised++,
    );

    expect(result, 'ran');
    expect(raised, 0);
  });

  test('a native floor that cannot be set never stops the app', () {
    final result = runWithDeviceLogFloor(
      () => 'ran',
      release: true,
      capabilities: androidCapabilities,
      raiseNativeFloor: () => throw ArgumentError('no liblog'),
    );

    expect(result, 'ran');
  });

  test('a debug or profile build leaves the native floor alone', () {
    var raised = 0;

    runWithDeviceLogFloor(
      () {},
      release: false,
      capabilities: androidCapabilities,
      raiseNativeFloor: () => raised++,
    );

    expect(raised, 0);
  });
}
