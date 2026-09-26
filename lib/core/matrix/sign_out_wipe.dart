import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../errors/best_effort.dart';
import '../platform/platform_capabilities.dart';
import '../settings/app_preferences_provider.dart';

const signedInMarkerKey = 'session.signed_in';

const stopDeliveryBeforeWipeBudget = Duration(seconds: 5);

const _appDataChannel = MethodChannel('zuno/app_data');

Future<void> _wipeAppData() async {
  if (await _appDataChannel.invokeMethod<bool>('wipe') != true) {
    throw StateError('the platform declined to wipe app data');
  }
}

Future<void> _keepAppData() async {}

class SignOutWipe {
  final SharedPreferences _prefs;
  final Future<void> Function() _wipe;
  bool _wiping = false;

  SignOutWipe(this._prefs, [this._wipe = _wipeAppData]);

  Future<void> onLoginState(
    bool loggedIn, {
    required Future<void> Function() stopDelivery,
  }) async {
    final hadSession = _prefs.getBool(signedInMarkerKey) ?? false;
    if (loggedIn) {
      if (!hadSession) await _prefs.setBool(signedInMarkerKey, true);
      return;
    }
    if (!hadSession || _wiping) return;
    _wiping = true;
    await runBestEffort(
      () => stopDelivery().timeout(stopDeliveryBeforeWipeBudget),
      label: 'stop notification delivery before wipe',
    );
    if (!await runBestEffort(_wipe, label: 'wipe app data')) return;
    await _prefs.remove(signedInMarkerKey);
    _wiping = false;
  }
}

final signOutWipeProvider = Provider<SignOutWipe>(
  (ref) => SignOutWipe(
    ref.watch(sharedPreferencesProvider),
    ref.watch(platformCapabilitiesProvider).nativeSignOutWipe
        ? _wipeAppData
        : _keepAppData,
  ),
);
