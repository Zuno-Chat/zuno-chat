import 'package:matrix/matrix.dart';

Future<void> refreshSession(
  Client client, {
  Duration settle = const Duration(seconds: 2),
}) async {
  final attempted = await _storedRefreshToken(client);
  if (attempted == null) {
    throw MatrixException.fromJson({
      'errcode': 'M_UNKNOWN_TOKEN',
      'error': 'No refresh token stored for this session',
    });
  }
  try {
    await _refresh(client);
  } catch (e) {
    if (!_isRefusal(e)) rethrow;
    await Future<void>.delayed(settle);
    if (await _storedRefreshToken(client) == attempted) rethrow;
    await _refresh(client);
  }
}

bool _isRefusal(Object failure) => switch (failure) {
  MatrixException(:final error) =>
    error == MatrixError.M_UNKNOWN_TOKEN || error == MatrixError.M_FORBIDDEN,
  OidcException(:final error) => error == 'invalid_grant',
  _ => false,
};

Future<void> _refresh(Client client) async {
  try {
    await client.refreshAccessToken();
  } catch (e, stack) {
    if (_isRefusal(e)) rethrow;
    final code = _failureCode(e);
    if (code == null) rethrow;
    Error.throwWithStackTrace(Exception('Token refresh failed: $code'), stack);
  }
}

String? _failureCode(Object failure) => switch (failure) {
  MatrixException(:final errcode) => errcode,
  OidcException(:final error) => error,
  _ => null,
};

Future<String?> _storedRefreshToken(Client client) async {
  final stored = await client.database.getClient(client.clientName);
  return stored?.tryGet<String>('refresh_token');
}
