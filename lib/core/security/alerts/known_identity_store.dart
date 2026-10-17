import 'package:shared_preferences/shared_preferences.dart';

const _prefix = 'security.known_identity.';

class KnownIdentityStore {
  final SharedPreferences _prefs;

  KnownIdentityStore(this._prefs);

  String? identityKey(String userId) => _prefs.getString('$_prefix$userId');

  Future<void> remember(String userId, String identityKey) async {
    if (this.identityKey(userId) == identityKey) return;
    await _prefs.setString('$_prefix$userId', identityKey);
  }
}
