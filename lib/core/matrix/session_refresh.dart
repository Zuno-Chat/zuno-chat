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
  } on MatrixException {
    await Future<void>.delayed(settle);
    if (await _storedRefreshToken(client) == attempted) rethrow;
    await _refresh(client);
  }
}

Future<void> _refresh(Client client) async {
  try {
    await client.refreshAccessToken();
  } on MatrixException catch (e, stack) {
    if (e.error == MatrixError.M_UNKNOWN_TOKEN ||
        e.error == MatrixError.M_FORBIDDEN) {
      rethrow;
    }
    Error.throwWithStackTrace(Exception('Token refresh failed: $e'), stack);
  }
}

Future<String?> _storedRefreshToken(Client client) async {
  final stored = await client.database.getClient(client.clientName);
  return stored?.tryGet<String>('refresh_token');
}
