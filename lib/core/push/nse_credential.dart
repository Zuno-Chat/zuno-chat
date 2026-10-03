import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../calls/serial_lock.dart';
import 'read_model/nse_app_channel.dart';
import 'zuno_push_api.dart';

class NseCredentialKeeper {
  NseCredentialKeeper({
    required this.mint,
    required this.channel,
    required this.prefs,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const mintedKey = 'nse.credential_minted_ms';
  static const refreshAfter = Duration(hours: 24);
  static const retryAfterAuth = Duration(hours: 1);

  final Future<ZunoPushResult<NseCredentialGrant>> Function() mint;
  final NseAppChannel channel;
  final SharedPreferences prefs;
  final DateTime Function() _now;
  final _lock = SerialLock();

  Future<bool> ensure({required bool allowed, bool afterAuthFailure = false}) =>
      _lock.run(
        () => _ensure(allowed: allowed, afterAuthFailure: afterAuthFailure),
      );

  Future<bool> _ensure({
    required bool allowed,
    required bool afterAuthFailure,
  }) async {
    if (!allowed) {
      if (prefs.containsKey(mintedKey)) {
        await channel.setCredential(null);
        await prefs.remove(mintedKey);
      }
      return false;
    }
    final minted = prefs.getInt(mintedKey);
    final age = minted == null
        ? null
        : _now().difference(DateTime.fromMillisecondsSinceEpoch(minted));
    final due =
        age == null ||
        age >= refreshAfter ||
        (afterAuthFailure && age >= retryAfterAuth);
    if (!due) return false;
    switch (await mint()) {
      case ZunoPushOk(value: final grant):
        if (!await channel.setCredential(
          grant.credential,
          expiresTs: grant.expiresTs,
        )) {
          return false;
        }
        await prefs.setInt(mintedKey, _now().millisecondsSinceEpoch);
        return true;
      case ZunoPushFailure(:final kind):
        debugPrint('zuno/nse: no credential for the extension yet ($kind)');
        return false;
    }
  }
}
