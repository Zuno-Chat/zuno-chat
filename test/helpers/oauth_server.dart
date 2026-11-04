import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'fake_matrix.dart';

const oauthMetadata = {
  'authorization_endpoint': 'https://auth.example.org/authorize',
  'code_challenge_methods_supported': ['S256'],
  'grant_types_supported': ['authorization_code', 'refresh_token'],
  'issuer': 'https://auth.example.org/',
  'prompt_values_supported': ['login', 'create'],
  'registration_endpoint': 'https://auth.example.org/register',
  'response_modes_supported': ['query', 'fragment'],
  'response_types_supported': ['code'],
  'revocation_endpoint': 'https://auth.example.org/revoke',
  'token_endpoint': 'https://auth.example.org/token',
};

class OAuthSignInDatabase extends FakeDatabaseApi {
  @override
  Future<Map<String, dynamic>?> getClient(String name) async => null;

  @override
  Future<void> storeClient({
    required String homeserverUrl,
    required String token,
    DateTime? tokenExpiresAt,
    String? refreshToken,
    required String userId,
    String? deviceId,
    String? deviceName,
    String? prevBatch,
    String? olmAccount,
    String? oidcClientId,
  }) async {}

  @override
  Future<Map<String, DeviceKeysList>> getUserDeviceKeys(Client client) async =>
      {};

  @override
  Future<List<Room>> getRoomList(Client client) async => [];

  @override
  Future<Map<String, BasicEvent>> getAccountData() async => {};

  @override
  Future<void> delete() async {}
}

class OAuthServer {
  final requests = <http.Request>[];
  int deviceAnswer = 200;
  String? displayName;
  http.Response? registrationAnswer;
  http.Response? tokenAnswer;

  http.Request? requestTo(String method, String path) => requests
      .where((r) => r.method == method && r.url.path == path)
      .firstOrNull;

  Future<http.Response> answer(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (path == '/_matrix/client/v1/auth_metadata') {
      return http.Response(jsonEncode(oauthMetadata), 200);
    }
    if (path == '/register') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      return registrationAnswer ??
          http.Response(jsonEncode({...body, 'client_id': 'client-1'}), 201);
    }
    if (path == '/token') {
      return tokenAnswer ??
          http.Response(
            jsonEncode({
              'access_token': 'at',
              'token_type': 'Bearer',
              'refresh_token': 'rt',
              'expires_in': 300,
            }),
            200,
          );
    }
    if (path == '/_matrix/client/v3/account/whoami') {
      return http.Response(
        jsonEncode({
          'user_id': '@alice:example.org',
          'device_id': 'ABCDEFGHIJ',
        }),
        200,
      );
    }
    if (request.method == 'PUT' &&
        path.startsWith('/_matrix/client/v3/devices/')) {
      return deviceAnswer == 200
          ? http.Response('{}', 200)
          : http.Response(
              jsonEncode({
                'errcode': 'M_UNRECOGNIZED',
                'error': 'Unrecognized',
              }),
              404,
            );
    }
    if (displayName != null && path.endsWith('/displayname')) {
      return http.Response(jsonEncode({'displayname': displayName}), 200);
    }
    if (path.endsWith('/sync')) {
      return http.Response(jsonEncode({'next_batch': 's1'}), 200);
    }
    return http.Response(jsonEncode({'errcode': 'M_NOT_FOUND'}), 404);
  }
}

Uri oauthCallbackFor(Uri authorization, {String code = 'c1', String? state}) =>
    Uri.parse(
      'chat.zuno:/oauth?code=$code'
      '&state=${state ?? authorization.queryParameters['state']}',
    );
