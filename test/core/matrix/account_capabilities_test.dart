import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/account_capabilities.dart';

import '../../helpers/caught_reports.dart';
import '../../helpers/fake_http.dart';
import '../../helpers/fake_matrix.dart';
import '../../helpers/oauth_server.dart';
import '../../helpers/pump_until.dart';

final _now = DateTime(2026, 11, 4, 12);

const _accountPage = 'https://account.example.org/account/';

const _masActions = [
  'org.matrix.profile',
  'org.matrix.sessions_list',
  'org.matrix.session_view',
  'org.matrix.session_end',
  'org.matrix.devices_list',
  'org.matrix.device_view',
  'org.matrix.device_delete',
  'org.matrix.cross_signing_reset',
];

Map<String, Object?> _metadata({
  String? accountPage = _accountPage,
  List<String>? actions = _masActions,
}) => {
  ...oauthMetadata,
  'account_management_uri': ?accountPage,
  'account_management_actions_supported': ?actions,
};

Set<AccountManagementActionsSupported> _actionsOf(List<String> names) => {
  ...?GetAuthMetadataResponse.fromJson(_metadata(actions: names))
      .accountManagementActionsSupported,
};

void main() {
  late CachingFakeDatabaseApi database;
  late List<http.Request> requests;
  late Object Function() answer;
  late Object Function() answerMetadata;

  Client client() {
    final built = buildTestClient(
      userId: '@me:example.org',
      database: database,
      httpClient: FakeHttpClient((request) async {
        requests.add(request);
        final body = request.url.path == '/_matrix/client/v1/auth_metadata'
            ? answerMetadata()
            : answer();
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
    Object? accountPage,
    bool withAccountPage = true,
  }) {
    database.cache['zuno.account_capabilities'] = (
      content: {
        'user_id': ?userId,
        'saved_at': _now.subtract(ago).millisecondsSinceEpoch,
        'change_password': password,
        'get_login_token': token,
        if (withAccountPage) 'account_page': accountPage,
      },
      savedAt: _now,
    );
  }

  Map<String, Object?>? savedCopy() =>
      database.cache['zuno.account_capabilities']?.content;

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
    answerMetadata = () => http.Response(
      jsonEncode({'errcode': 'M_UNRECOGNIZED', 'error': 'Unrecognized'}),
      404,
    );
  });

  void saveSdkMetadata(Map<String, Object?> metadata) =>
      database.cache['auth_metadata'] = (
        content: metadata,
        savedAt: deviceClockNow(),
      );

  List<String> paths() => [for (final request in requests) request.url.path];

  int metadataRequests() => paths()
      .where((path) => path == '/_matrix/client/v1/auth_metadata')
      .length;

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

  group('the account page link', () {
    test('links an advertised action with its device', () {
      final page = AccountPage(
        Uri.parse(_accountPage),
        _actionsOf(_masActions),
      );

      expect(
        page.linkFor(
          AccountManagementActionsSupported.orgMatrixDeviceDelete,
          deviceId: 'TABLET',
        ),
        Uri.parse(
          '$_accountPage?action=org.matrix.device_delete&device_id=TABLET',
        ),
      );
      expect(
        page.linkFor(AccountManagementActionsSupported.orgMatrixDevicesList),
        Uri.parse('$_accountPage?action=org.matrix.devices_list'),
      );
    });

    test('falls back to the plain page for an unadvertised action', () {
      final page = AccountPage(
        Uri.parse(_accountPage),
        _actionsOf(_masActions),
      );

      expect(
        page.linkFor(
          AccountManagementActionsSupported.orgMatrixAccountDeactivate,
        ),
        Uri.parse(_accountPage),
      );
    });

    test('keeps the query the server gave its page', () {
      final page = AccountPage(Uri.parse('$_accountPage?lang=da'), {
        AccountManagementActionsSupported.orgMatrixDeviceDelete,
      });

      expect(
        page
            .linkFor(
              AccountManagementActionsSupported.orgMatrixDeviceDelete,
              deviceId: 'TABLET',
            )
            .queryParameters,
        {
          'lang': 'da',
          'action': 'org.matrix.device_delete',
          'device_id': 'TABLET',
        },
      );
    });
  });

  group('the account page', () {
    void passwordOff() => answer = () => body(password: false, token: true);

    test('a server that allows password change has no account page and asks '
        'for no metadata', () async {
      answer = () => body(password: true);
      answerMetadata = () => _metadata();

      final result = await read();

      expect(result.accountPage, isNull);
      expect(paths(), ['/_matrix/client/v3/capabilities']);
    });

    test(
      'a saved copy that allows password change asks for no metadata',
      () async {
        save(const Duration(days: 1), password: true);
        saveSdkMetadata(_metadata());

        final result = await read();

        expect(result.accountPage, isNull);
        expect(requests, isEmpty);
      },
    );

    test('password change off reads the account page from the SDK\'s saved '
        'metadata', () async {
      passwordOff();
      saveSdkMetadata(_metadata());

      final result = await read();

      expect(paths(), ['/_matrix/client/v3/capabilities']);
      expect(result.canChangePassword, isFalse);
      expect(result.canMintSignInCodes, isTrue);
      expect(result.accountPage?.uri, Uri.parse(_accountPage));
      expect(
        result.accountPage?.actions,
        contains(AccountManagementActionsSupported.orgMatrixDeviceDelete),
      );
    });

    test('password change off asks the server for its metadata when the SDK '
        'has none, and the SDK keeps it', () async {
      answer = () => body(password: false, token: false);
      answerMetadata = () => _metadata();

      final result = await read();

      expect(paths(), [
        '/_matrix/client/v3/capabilities',
        '/_matrix/client/v1/auth_metadata',
      ]);
      expect(result.accountPage?.uri, Uri.parse(_accountPage));
      expect(result.canMintSignInCodes, isFalse);
      expect(database.cache['auth_metadata'], isNotNull);
    });

    test('no account page when the server has no metadata', () async {
      passwordOff();

      late AccountCapabilities result;
      final reports = await reportsDuring(() async => result = await read());

      expect(metadataRequests(), 1);
      expect(result.accountPage, isNull);
      expect(result.canChangePassword, isFalse);
      expect(result.canMintSignInCodes, isTrue);
      expect(reports, isEmpty);
    });

    test('no account page when the metadata names none', () async {
      passwordOff();
      saveSdkMetadata(_metadata(accountPage: null));

      final result = await read();

      expect(result.accountPage, isNull);
    });

    test('an account page that is not a web page is not used', () async {
      passwordOff();
      saveSdkMetadata(_metadata(accountPage: 'intent://account'));

      final result = await read();

      expect(result.accountPage, isNull);
    });

    test('an account page without listed actions opens plain', () async {
      passwordOff();
      saveSdkMetadata(_metadata(actions: null));

      final result = await read();

      expect(
        result.accountPage?.linkFor(
          AccountManagementActionsSupported.orgMatrixDeviceDelete,
          deviceId: 'TABLET',
        ),
        Uri.parse(_accountPage),
      );
    });

    test('a server failure leaves no account page, is not reported and is '
        'not saved as none', () async {
      passwordOff();
      answerMetadata = () => http.Response('<html>Bad gateway</html>', 502);

      late AccountCapabilities result;
      final reports = await reportsDuring(() async => result = await read());

      expect(result.accountPage, isNull);
      expect(result.canChangePassword, isFalse);
      expect(reports, isEmpty);
      expect(savedCopy(), isNull);

      await read();

      expect(metadataRequests(), 2);
    });

    test('a server failure keeps the account page from a stale copy', () async {
      save(
        const Duration(days: 4),
        accountPage: {
          'uri': _accountPage,
          'actions': ['org.matrix.device_delete'],
        },
      );
      passwordOff();
      answerMetadata = () => http.Response('<html>Bad gateway</html>', 502);

      final result = await read();

      expect(result.accountPage?.uri, Uri.parse(_accountPage));
      expect(
        result.accountPage?.linkFor(
          AccountManagementActionsSupported.orgMatrixDeviceDelete,
          deviceId: 'TABLET',
        ),
        Uri.parse(
          '$_accountPage?action=org.matrix.device_delete&device_id=TABLET',
        ),
      );
    });

    test('two reads within 3 days on a server without an account page ask '
        'for metadata once', () async {
      passwordOff();

      await read();
      final second = await read();

      expect(metadataRequests(), 1);
      expect(paths(), hasLength(2));
      expect(second.accountPage, isNull);
      expect(second.canChangePassword, isFalse);
    });

    test('an account page survives in the saved copy', () async {
      passwordOff();
      answerMetadata = () => _metadata();
      await read();
      database.cache.remove('auth_metadata');
      requests.clear();

      final result = await read();

      expect(requests, isEmpty);
      expect(result.accountPage?.uri, Uri.parse(_accountPage));
      expect(result.accountPage?.actions, _actionsOf(_masActions));
      expect(
        result.accountPage?.linkFor(
          AccountManagementActionsSupported.orgMatrixAccountDeactivate,
        ),
        Uri.parse(_accountPage),
      );
    });

    test('a copy missing its account page is no copy', () async {
      save(const Duration(days: 1), withAccountPage: false);
      passwordOff();
      answerMetadata = () => _metadata();

      final result = await read();

      expect(paths(), [
        '/_matrix/client/v3/capabilities',
        '/_matrix/client/v1/auth_metadata',
      ]);
      expect(result.accountPage?.uri, Uri.parse(_accountPage));
      expect(savedCopy()?['account_page'], isNotNull);
    });

    test('a copy missing its account page is no fallback when the server '
        'fails', () async {
      save(const Duration(days: 1), withAccountPage: false, token: false);
      answer = () => http.Response('{"errcode":"M_UNKNOWN"}', 500);

      final result = await read();

      expect(result.canChangePassword, isTrue);
      expect(result.canMintSignInCodes, isTrue);
      expect(metadataRequests(), 0);
    });

    test('a saved account page of the wrong shape is not used', () async {
      save(const Duration(days: 1), accountPage: {'uri': 5});
      passwordOff();

      await read();

      expect(paths(), contains('/_matrix/client/v3/capabilities'));
    });
  });

  group('a known answer', () {
    test('is none while loading', () {
      expect(const AsyncLoading<AccountCapabilities>().known, isNull);
    });

    test('is the answer once read', () {
      const answer = AccountCapabilities(canChangePassword: false);

      expect(const AsyncData(answer).known, same(answer));
    });

    test('is the defaults when the read failed', () {
      final known = AsyncError<AccountCapabilities>(
        StateError('unreadable'),
        StackTrace.empty,
      ).known;

      expect(known?.canChangePassword, isTrue);
      expect(known?.canMintSignInCodes, isTrue);
      expect(known?.accountPage, isNull);
    });
  });
}
