import 'package:matrix/matrix.dart';

class SessionEnded implements Exception {
  const SessionEnded(this.code);

  final String code;

  @override
  String toString() => 'Session ended: $code';
}

Future<void> refreshSession(
  Client client, {
  Duration settle = const Duration(seconds: 2),
}) async {
  if (!client.isLogged()) return _endSession(client, 'signed out');
  final attempted = await _storedRefreshToken(client);
  if (attempted == null) return _endSession(client, 'no refresh token stored');
  var refusal = await _refusalOf(client);
  if (refusal == null) return;
  await Future<void>.delayed(settle);
  if (await _storedRefreshToken(client) != attempted) {
    refusal = await _refusalOf(client);
    if (refusal == null) return;
  }
  return _endSession(client, refusal);
}

Future<void> _endSession(Client client, String code) async {
  await client.clear(reason: SessionClearReason.softLogoutRefreshFailed);
  throw SessionEnded(code);
}

Future<String?> _refusalOf(Client client) async {
  try {
    await client.refreshAccessToken();
    return null;
  } catch (e, stack) {
    final code = _failureCode(e);
    if (code == null) rethrow;
    if (_isRefusal(e)) return code;
    Error.throwWithStackTrace(Exception('Token refresh failed: $code'), stack);
  }
}

bool _isRefusal(Object failure) => switch (failure) {
  MatrixException(:final error) =>
    error == MatrixError.M_UNKNOWN_TOKEN || error == MatrixError.M_FORBIDDEN,
  OidcException(:final error) => error == 'invalid_grant',
  _ => false,
};

String? _failureCode(Object failure) => switch (failure) {
  MatrixException(:final errcode) => errcode,
  OidcException(:final error) => error,
  _ => null,
};

Future<String?> _storedRefreshToken(Client client) async {
  final stored = await client.database.getClient(client.clientName);
  return stored?.tryGet<String>('refresh_token');
}
