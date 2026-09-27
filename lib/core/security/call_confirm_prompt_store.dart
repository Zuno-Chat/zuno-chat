import 'package:shared_preferences/shared_preferences.dart';

const _prefix = 'security.call_confirm_declined.';

class CallConfirmPromptStore {
  final SharedPreferences _prefs;

  CallConfirmPromptStore(this._prefs);

  bool declined(String userId) => _prefs.getBool('$_prefix$userId') ?? false;

  Future<void> decline(String userId) =>
      _prefs.setBool('$_prefix$userId', true);
}
