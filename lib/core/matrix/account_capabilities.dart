import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../errors/caught_errors.dart';
import '../errors/connection_error.dart';
import 'matrix_client_provider.dart';

const accountCapabilitiesLifetime = Duration(days: 3);

const _cacheKey = 'zuno.account_capabilities';

class AccountCapabilities {
  const AccountCapabilities({
    this.canChangePassword = true,
    this.canMintSignInCodes = true,
  });

  final bool canChangePassword;
  final bool canMintSignInCodes;
}

typedef _Saved = ({AccountCapabilities capabilities, DateTime savedAt});

Future<_Saved?> _readSaved(Client client) async {
  final saved = await client.database.getCustomCacheObject(_cacheKey);
  final content = saved?.content;
  if (content == null) return null;
  if (content['user_id'] != client.userID) return null;
  final ms = content['saved_at'];
  final password = content['change_password'];
  final token = content['get_login_token'];
  if (ms is! int || password is! bool || token is! bool) return null;
  return (
    capabilities: AccountCapabilities(
      canChangePassword: password,
      canMintSignInCodes: token,
    ),
    savedAt: DateTime.fromMillisecondsSinceEpoch(ms),
  );
}

void _report(Object error, StackTrace stack) {
  if (!isConnectionError(error) && error is! MatrixException) {
    reportCaught('read account capabilities', error, stack);
  }
}

Future<AccountCapabilities> readAccountCapabilities(Client client) async {
  _Saved? saved;
  try {
    saved = await _readSaved(client);
  } catch (error, stack) {
    _report(error, stack);
  }
  final now = clock.now();
  if (saved != null) {
    final age = now.difference(saved.savedAt);
    if (!age.isNegative && age < accountCapabilitiesLifetime) {
      return saved.capabilities;
    }
  }
  final AccountCapabilities result;
  try {
    final fetched = await client.getCapabilities();
    result = AccountCapabilities(
      canChangePassword: fetched.mChangePassword?.enabled ?? true,
      canMintSignInCodes: fetched.mGetLoginToken?.enabled ?? false,
    );
  } catch (error, stack) {
    _report(error, stack);
    return saved?.capabilities ?? const AccountCapabilities();
  }
  try {
    await client.database.cacheCustomObject(_cacheKey, {
      'user_id': client.userID,
      'saved_at': now.millisecondsSinceEpoch,
      'change_password': result.canChangePassword,
      'get_login_token': result.canMintSignInCodes,
    });
  } catch (error, stack) {
    _report(error, stack);
  }
  return result;
}

final accountCapabilitiesProvider =
    FutureProvider.autoDispose<AccountCapabilities>(
      (ref) => readAccountCapabilities(ref.watch(matrixClientProvider)),
    );
