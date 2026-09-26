import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/matrix/sign_out_wipe.dart';

void main() {
  late SharedPreferences prefs;
  late List<String> calls;
  late SignOutWipe wipe;

  Future<void> stopDelivery() async => calls.add('stop');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    calls = [];
    wipe = SignOutWipe(prefs, () async => calls.add('wipe'));
  });

  test('a signed-in device is remembered and nothing is wiped', () async {
    await wipe.onLoginState(true, stopDelivery: stopDelivery);

    expect(prefs.getBool(signedInMarkerKey), isTrue);
    expect(calls, isEmpty);
  });

  test('signing out after a session stops delivery, then wipes', () async {
    await wipe.onLoginState(true, stopDelivery: stopDelivery);

    await wipe.onLoginState(false, stopDelivery: stopDelivery);

    expect(calls, ['stop', 'wipe']);
  });

  test('a session left from an earlier run is wiped at launch', () async {
    await prefs.setBool(signedInMarkerKey, true);

    await wipe.onLoginState(false, stopDelivery: stopDelivery);

    expect(calls, ['stop', 'wipe']);
  });

  test('a device that never signed in is never wiped', () async {
    await wipe.onLoginState(false, stopDelivery: stopDelivery);

    expect(calls, isEmpty);
  });

  test('a failed delivery stop does not block the wipe', () async {
    await prefs.setBool(signedInMarkerKey, true);

    await wipe.onLoginState(
      false,
      stopDelivery: () async => throw Exception('offline'),
    );

    expect(calls, ['wipe']);
  });

  test('a delivery stop that hangs is given up on, then the wipe runs', () {
    fakeAsync((async) {
      prefs.setBool(signedInMarkerKey, true);
      unawaited(
        wipe.onLoginState(false, stopDelivery: () => Completer<void>().future),
      );

      async.elapse(stopDeliveryBeforeWipeBudget - const Duration(seconds: 1));
      expect(calls, isEmpty);

      async.elapse(const Duration(seconds: 2));
      expect(calls, ['wipe']);
    });
  });

  test('repeated sign-out states wipe once', () async {
    await prefs.setBool(signedInMarkerKey, true);

    await Future.wait([
      wipe.onLoginState(false, stopDelivery: stopDelivery),
      wipe.onLoginState(false, stopDelivery: stopDelivery),
    ]);

    expect(calls.where((c) => c == 'wipe'), hasLength(1));
  });

  test('a wipe the platform refuses is not fatal', () async {
    await prefs.setBool(signedInMarkerKey, true);
    final refusing = SignOutWipe(prefs, () async => throw Exception('no'));

    await refusing.onLoginState(false, stopDelivery: stopDelivery);
  });
}
