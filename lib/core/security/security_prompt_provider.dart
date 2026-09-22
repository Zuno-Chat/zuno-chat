import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../matrix/matrix_client_provider.dart';
import '../settings/app_preferences_provider.dart';
import 'account_security_status.dart';
import 'security_prompt.dart';
import 'security_providers.dart';

const _firstUseKey = 'security.first_use_ms';
const _lastPromptedKey = 'security.recovery_prompt_ms';

class SecurityPromptStore {
  final SharedPreferences _prefs;

  SecurityPromptStore(this._prefs);

  bool promptInFlight = false;

  DateTime? _lastPromptedInMemory;

  Future<DateTime> firstUse() async {
    final stored = _prefs.getInt(_firstUseKey);
    if (stored != null) return DateTime.fromMillisecondsSinceEpoch(stored);
    final now = DateTime.now();
    await _prefs.setInt(_firstUseKey, now.millisecondsSinceEpoch);
    return now;
  }

  DateTime? lastPrompted() {
    final stored = _prefs.getInt(_lastPromptedKey);
    final persisted = stored == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(stored);
    final inMemory = _lastPromptedInMemory;
    if (persisted == null || inMemory == null) return persisted ?? inMemory;
    return persisted.isAfter(inMemory) ? persisted : inMemory;
  }

  Future<void> markPrompted() {
    final now = DateTime.now();
    _lastPromptedInMemory = now;
    return _prefs.setInt(_lastPromptedKey, now.millisecondsSinceEpoch);
  }
}

final securityPromptStoreProvider = Provider<SecurityPromptStore>((ref) {
  return SecurityPromptStore(ref.watch(sharedPreferencesProvider));
});

final securityPromptProvider = FutureProvider<SecurityPromptDecision>((
  ref,
) async {
  final facts = await ref.watch(accountSecurityFactsProvider.future);
  final client = ref.watch(matrixClientProvider);
  final store = ref.watch(securityPromptStoreProvider);
  return securityPromptDecision(
    status: accountSecurityStatus(facts),
    firstUse: await store.firstUse(),
    lastPrompted: store.lastPrompted(),
    now: DateTime.now(),
    deviceCount: client.userDeviceKeys[client.userID]?.deviceKeys.length ?? 1,
    hasConversations: client.rooms.any(
      (room) => room.membership == Membership.join,
    ),
  );
});
