import 'package:shared_preferences/shared_preferences.dart';

const _prefix = 'security.known_devices.';

class KnownDevicesStore {
  final SharedPreferences _prefs;

  KnownDevicesStore(this._prefs);

  Set<String>? knownDeviceIds(String userId) =>
      _prefs.getStringList('$_prefix$userId')?.toSet();

  Future<void> remember(String userId, Set<String> deviceIds) async {
    final known = knownDeviceIds(userId);
    if (known != null && known.containsAll(deviceIds)) return;
    await _prefs.setStringList(
      '$_prefix$userId',
      {...?known, ...deviceIds}.toList()..sort(),
    );
  }

  Future<void> forget(String userId) => _prefs.remove('$_prefix$userId');
}
