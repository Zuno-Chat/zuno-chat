import 'package:matrix/matrix.dart';

Future<String> bearerAuthorization(Client client) async {
  await client.ensureNotSoftLoggedOut();
  final token = client.accessToken;
  if (token == null) {
    throw StateError('Not logged in — no access token to send.');
  }
  return 'Bearer $token';
}
