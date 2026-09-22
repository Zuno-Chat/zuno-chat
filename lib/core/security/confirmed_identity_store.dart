import 'package:shared_preferences/shared_preferences.dart';

const _prefix = 'security.confirmed_identity.';
const _atPrefix = 'security.confirmed_identity_at.';

class ConfirmedIdentityStore {
  final SharedPreferences _prefs;

  ConfirmedIdentityStore(this._prefs);

  String? confirmedIdentityKey(String userId) =>
      _prefs.getString('$_prefix$userId');

  DateTime? confirmedAt(String userId) {
    final stored = _prefs.getInt('$_atPrefix$userId');
    return stored == null ? null : DateTime.fromMillisecondsSinceEpoch(stored);
  }

  Future<void> remember(String userId, String identityKey) async {
    await _prefs.setString('$_prefix$userId', identityKey);
    await _prefs.setInt(
      '$_atPrefix$userId',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> forget(String userId) async {
    await _prefs.remove('$_prefix$userId');
    await _prefs.remove('$_atPrefix$userId');
  }

  Future<void> forgetAll() async {
    final keys = _prefs
        .getKeys()
        .where((k) => k.startsWith(_prefix) || k.startsWith(_atPrefix))
        .toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
}
