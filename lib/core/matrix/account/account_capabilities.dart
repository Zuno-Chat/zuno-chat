import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../errors/caught_errors.dart';
import '../auth/server_choice.dart';
import '../client/matrix_client_provider.dart';
import '../http/typed_server_answers.dart';
import 'saved_server_answer.dart';

const accountCapabilitiesLifetime = Duration(days: 3);

const _cacheKey = 'zuno.account_capabilities';

class AccountPage {
  const AccountPage(this.uri, this.actions);

  final Uri uri;
  final Set<AccountManagementActionsSupported> actions;

  Uri linkFor(AccountManagementActionsSupported action, {String? deviceId}) {
    if (!actions.contains(action)) return uri;
    return uri.replace(
      queryParameters: {
        ...uri.queryParametersAll,
        'action': action.name,
        'device_id': ?deviceId,
      },
    );
  }
}

class AccountCapabilities {
  const AccountCapabilities({
    this.canChangePassword = true,
    this.canMintSignInCodes = true,
    this.accountPage,
  });

  final bool canChangePassword;
  final bool canMintSignInCodes;
  final AccountPage? accountPage;
}

typedef _Saved = ({AccountCapabilities capabilities, DateTime savedAt});

Future<_Saved?> _readSaved(Client client) async {
  final saved = await readSavedServerAnswer(client, _cacheKey);
  if (saved == null) return null;
  final content = saved.content;
  final password = content['change_password'];
  final token = content['get_login_token'];
  if (password is! bool || token is! bool) return null;
  if (!content.containsKey('account_page')) return null;
  final AccountPage? accountPage;
  switch (content['account_page']) {
    case null:
      accountPage = null;
    case {'uri': final String uri, 'actions': final List<Object?> actions}:
      accountPage = AccountPage(Uri.parse(uri), {
        for (final action in AccountManagementActionsSupported.values)
          if (actions.contains(action.name)) action,
      });
    default:
      return null;
  }
  return (
    capabilities: AccountCapabilities(
      canChangePassword: password,
      canMintSignInCodes: token,
      accountPage: accountPage,
    ),
    savedAt: saved.savedAt,
  );
}

Map<String, Object?>? _savedAccountPage(AccountPage? page) => page == null
    ? null
    : {
        'uri': page.uri.toString(),
        'actions': [for (final action in page.actions) action.name],
      };

void _report(String label, Object error, StackTrace stack) {
  if (!isServerOrNetworkFailure(error)) reportCaught(label, error, stack);
}

const _capabilitiesLabel = 'read account capabilities';

Future<AccountCapabilities> readAccountCapabilities(Client client) async {
  _Saved? saved;
  try {
    saved = await _readSaved(client);
  } catch (error, stack) {
    _report(_capabilitiesLabel, error, stack);
  }
  if (saved != null && isFresh(saved.savedAt, accountCapabilitiesLifetime)) {
    return saved.capabilities;
  }
  final Capabilities fetched;
  try {
    fetched = await client.getCapabilities();
  } catch (error, stack) {
    _report(_capabilitiesLabel, error, stack);
    return saved?.capabilities ?? const AccountCapabilities();
  }
  final canChangePassword = fetched.mChangePassword?.enabled ?? true;
  final canMintSignInCodes = fetched.mGetLoginToken?.enabled ?? false;
  final AccountPage? accountPage;
  try {
    accountPage = canChangePassword ? null : await _readAccountPage(client);
  } catch (error, stack) {
    _report('read account page', error, stack);
    return AccountCapabilities(
      canChangePassword: canChangePassword,
      canMintSignInCodes: canMintSignInCodes,
      accountPage: saved?.capabilities.accountPage,
    );
  }
  final result = AccountCapabilities(
    canChangePassword: canChangePassword,
    canMintSignInCodes: canMintSignInCodes,
    accountPage: accountPage,
  );
  try {
    await saveServerAnswer(client, _cacheKey, {
      'change_password': result.canChangePassword,
      'get_login_token': result.canMintSignInCodes,
      'account_page': _savedAccountPage(result.accountPage),
    });
  } catch (error, stack) {
    _report(_capabilitiesLabel, error, stack);
  }
  return result;
}

Future<AccountPage?> _readAccountPage(Client client) async {
  final GetAuthMetadataResponse metadata;
  try {
    metadata = await client.getAuthMetadata();
  } catch (error) {
    if (meansNoAuthMetadata(error)) return null;
    rethrow;
  }
  final uri = metadata.accountManagementUri;
  if (uri == null || !uri.isScheme('https')) return null;
  return AccountPage(uri, {...?metadata.accountManagementActionsSupported});
}

extension KnownAccountCapabilities on AsyncValue<AccountCapabilities> {
  AccountCapabilities? get known => hasValue
      ? value
      : hasError
      ? const AccountCapabilities()
      : null;
}

final accountCapabilitiesProvider =
    FutureProvider.autoDispose<AccountCapabilities>(
      (ref) => readAccountCapabilities(ref.watch(matrixClientProvider)),
    );
