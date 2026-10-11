import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../errors/best_effort.dart';
import '../platform/platform_capabilities.dart';
import '../settings/app_preferences_provider.dart';
import 'database_compaction.dart';
import 'matrix_client_provider.dart';

const signedInMarkerKey = 'session.signed_in';

const stopDeliveryBeforeWipeBudget = Duration(seconds: 5);

const _appDataChannel = MethodChannel('zuno/app_data');

Future<void> _wipeAppData([Map<String, Object?>? arguments]) async {
  if (await _appDataChannel.invokeMethod<bool>('wipe', arguments) != true) {
    throw StateError('the platform declined to wipe app data');
  }
}

Future<void> _keepAppData() async {}

final signOutWipeProvider = NotifierProvider<SignOutWipe, bool>(
  SignOutWipe.new,
);

class SignOutWipe extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> onLoginState(
    bool loggedIn, {
    required Future<void> Function() stopDelivery,
  }) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final hadSession = prefs.getBool(signedInMarkerKey) ?? false;
    if (loggedIn) {
      if (!hadSession) await prefs.setBool(signedInMarkerKey, true);
      return;
    }
    if (!hadSession || state) return;
    state = true;
    try {
      await runBestEffort(
        () => stopDelivery().timeout(stopDeliveryBeforeWipeBudget),
        label: 'stop notification delivery before wipe',
      );
      final wipe = ref.read(appDataWipeProvider);
      if (!await runBestEffort(wipe, label: 'wipe app data')) return;
      await prefs.remove(signedInMarkerKey);
    } finally {
      state = false;
    }
  }
}

final databaseVacuumProvider = Provider<Future<void> Function()>(
  (ref) =>
      () async =>
          liveDatabase(ref.read(matrixClientProvider))?.execute('VACUUM'),
);

final liveDatabasePathProvider = Provider<String? Function()>(
  (ref) =>
      () => liveDatabase(ref.read(matrixClientProvider))?.path,
);

Future<void> Function() _wipeKeepingProcess(
  Future<void> Function() vacuum,
  String? Function() databasePath,
  SharedPreferences prefs,
) => () async {
  await runBestEffort(vacuum, label: 'vacuum the database before the wipe');
  final keep = databasePath();
  if (keep == null) {
    throw StateError('the open database is unknown, so nothing is wiped');
  }
  await _wipeAppData({
    'keep': [keep],
  });
  await prefs.reload();
};

final appDataWipeProvider = Provider<Future<void> Function()>((ref) {
  final capabilities = ref.watch(platformCapabilitiesProvider);
  if (!capabilities.nativeSignOutWipe) return _keepAppData;
  if (!capabilities.signOutWipeKeepsProcess) return _wipeAppData;
  return _wipeKeepingProcess(
    ref.watch(databaseVacuumProvider),
    ref.watch(liveDatabasePathProvider),
    ref.watch(sharedPreferencesProvider),
  );
});
