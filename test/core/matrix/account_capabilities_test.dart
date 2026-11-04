import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/account_capabilities.dart';

import '../../helpers/fake_http.dart';
import '../../helpers/fake_matrix.dart';

final _now = DateTime(2026, 11, 4, 12);

void main() {
  late CachingFakeDatabaseApi database;
  late List<http.Request> requests;
  late Object Function() answer;

  Client client() {
    final built = buildTestClient(
      userId: '@me:example.org',
      database: database,
      httpClient: FakeHttpClient((request) async {
        requests.add(request);
        final body = answer();
        if (body is http.Response) return body;
        return http.Response(jsonEncode(body), 200);
      }),
    )..homeserver = Uri.parse('https://example.org');
    built.bearerToken = 'token';
    return built;
  }

  void save(
    Duration ago, {
    bool password = false,
    bool token = true,
    String? userId = '@me:example.org',
  }) {
    database.cache['zuno.account_capabilities'] = (
      content: {
        'user_id': ?userId,
        'saved_at': _now.subtract(ago).millisecondsSinceEpoch,
        'change_password': password,
        'get_login_token': token,
      },
      savedAt: _now,
    );
  }

  Map<String, Object?> body({bool? password, bool? token}) => {
    'capabilities': {
      if (password != null) 'm.change_password': {'enabled': password},
      if (token != null) 'm.get_login_token': {'enabled': token},
    },
  };

  Future<AccountCapabilities> read() =>
      withClock(Clock.fixed(_now), () => readAccountCapabilities(client()));

  setUp(() {
    database = CachingFakeDatabaseApi();
    requests = [];
    answer = () => body();
  });

  test('a fresh saved copy answers without asking the server', () async {
    save(const Duration(days: 2));

    final result = await read();

    expect(requests, isEmpty);
    expect(result.canChangePassword, isFalse);
    expect(result.canMintSignInCodes, isTrue);
  });

  test('a copy saved by another account is not used', () async {
    save(const Duration(days: 1), userId: '@other:example.org');
    answer = () => body(password: true, token: false);

    final result = await read();

    expect(requests, hasLength(1));
    expect(result.canChangePassword, isTrue);
    expect(result.canMintSignInCodes, isFalse);
  });

  test('a copy saved without an account is not used', () async {
    save(const Duration(days: 1), userId: null);

    await read();

    expect(requests, hasLength(1));
  });

  test('a stale saved copy is asked again and saved', () async {
    save(const Duration(days: 4));
    answer = () => body(password: true, token: false);

    final result = await read();

    expect(requests, hasLength(1));
    expect(result.canChangePassword, isTrue);
    expect(result.canMintSignInCodes, isFalse);
    final saved = database.cache['zuno.account_capabilities']!.content;
    expect(saved['saved_at'], _now.millisecondsSinceEpoch);
    expect(saved['change_password'], isTrue);
    expect(saved['get_login_token'], isFalse);
  });

  test('no saved copy asks the server', () async {
    await read();

    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/_matrix/client/v3/capabilities');
  });

  test('a copy saved in the future is stale', () async {
    save(const Duration(hours: -1));

    await read();

    expect(requests, hasLength(1));
  });

  test(
    'absent capabilities allow password change and not sign-in codes',
    () async {
      final result = await read();

      expect(result.canChangePassword, isTrue);
      expect(result.canMintSignInCodes, isFalse);
    },
  );

  test('disabled password change and enabled sign-in codes are read as '
      'such', () async {
    answer = () => body(password: false, token: true);

    final result = await read();

    expect(result.canChangePassword, isFalse);
    expect(result.canMintSignInCodes, isTrue);
  });

  test('a failed request falls back to a stale copy', () async {
    save(const Duration(days: 4));
    answer = () => http.Response('{"errcode":"M_UNKNOWN"}', 500);

    final result = await read();

    expect(requests, hasLength(1));
    expect(result.canChangePassword, isFalse);
    expect(result.canMintSignInCodes, isTrue);
  });

  test('a failed save still returns the fetched answer', () async {
    database.failSave = true;
    answer = () => body(password: false, token: true);

    final result = await read();

    expect(result.canChangePassword, isFalse);
    expect(result.canMintSignInCodes, isTrue);
  });

  test('with no copy, both actions stay offered', () async {
    answer = () => http.Response('{"errcode":"M_UNKNOWN"}', 500);

    final result = await read();

    expect(result.canChangePassword, isTrue);
    expect(result.canMintSignInCodes, isTrue);
  });
}
