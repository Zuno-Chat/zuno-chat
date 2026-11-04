import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/homeserver.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/server_choice.dart';
import 'package:zuno/core/network/app_http_overrides.dart';

import '../../helpers/caught_reports.dart';
import '../../helpers/fake_http.dart';
import '../../helpers/fake_matrix.dart';

void main() {
  final requests = <Uri>[];
  final example = Uri.parse('https://example.org');
  const discoveryPath = '/.well-known/matrix/client';
  const registerPath = '/_matrix/client/v3/register';

  setUp(requests.clear);

  List<Uri> requestsTo(String path) =>
      requests.where((url) => url.path == path).toList();

  http.Response notFound() =>
      http.Response(jsonEncode({'errcode': 'M_NOT_FOUND'}), 404);

  http.Response signUpFlows(List<List<String>> flows) => http.Response(
    jsonEncode({
      'session': 'uia1',
      'flows': [
        for (final stages in flows) {'stages': stages},
      ],
    }),
    401,
  );

  http.Response openSignUp() => signUpFlows(const [
    ['m.login.dummy'],
  ]);

  http.Response codeSignUp() => signUpFlows(const [
    ['m.login.registration_token', 'm.login.dummy'],
  ]);

  http.Response closedSignUp() =>
      http.Response(jsonEncode({'errcode': 'M_FORBIDDEN'}), 403);

  http.Response announcing(String apiHost) => http.Response(
    jsonEncode({
      'm.homeserver': {'base_url': apiHost},
      zunoRegisterAnnouncementKey: <String, Object?>{},
    }),
    200,
  );

  Future<SignUpPath> askSignUp(
    ProviderContainer container, [
    ServerChoice? choice,
  ]) async {
    final ServerChoice asked =
        choice ?? await container.read(homeserverProvider.future);
    container.listen(signUpPathProvider(asked), (_, _) {});
    return container.read(signUpPathProvider(asked).future);
  }

  (ProviderContainer, Client) setUpContainer({
    Set<String> down = const {},
    List<String> versions = const ['v1.1', 'v1.5'],
    Map<String, FakeHttpHandler> versionsAt = const {},
    FakeHttpHandler? discovery,
    FakeHttpHandler? register,
  }) {
    final client = buildTestClient(
      httpClient: FakeHttpClient((request) async {
        final url = request.url;
        requests.add(url);
        if (down.contains(url.host)) throw http.ClientException('offline');
        if (url.path == discoveryPath && discovery != null) {
          return discovery(request);
        }
        if (url.path.endsWith('/versions')) {
          if (versionsAt[url.host] case final answer?) return answer(request);
          return http.Response(jsonEncode({'versions': versions}), 200);
        }
        if (url.path == registerPath && register != null) {
          return register(request);
        }
        return notFound();
      }),
    );
    final container = ProviderContainer(
      overrides: [matrixClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    return (container, client);
  }

  test('zuno.chat is verified first, and nothing else is contacted', () async {
    final (container, client) = setUpContainer();

    final verified = await container.read(homeserverProvider.future);

    expect(
      verified,
      ServerChoice(
        officialHomeserver,
        apiHost: officialHomeserver,
        mailsSignUpCodes: false,
      ),
    );
    expect(client.homeserver?.host, 'zuno.chat');
    expect(requests.map((url) => url.host).toSet(), {'zuno.chat'});
  });

  test('a server that answers becomes the one to sign in to', () async {
    final (container, client) = setUpContainer();
    await container.read(homeserverProvider.future);

    await container.read(homeserverProvider.notifier).use(example);

    expect(
      container.read(homeserverProvider).value,
      ServerChoice(example, apiHost: example, mailsSignUpCodes: false),
    );
    expect(client.homeserver?.host, 'example.org');
  });

  test(
    'a server that does not answer leaves the previous one in place',
    () async {
      final (container, client) = setUpContainer(down: {'typo.example'});
      await container.read(homeserverProvider.future);
      final before = client.homeserver;

      await expectLater(
        container
            .read(homeserverProvider.notifier)
            .use(Uri.parse('https://typo.example')),
        throwsA(isA<http.ClientException>()),
      );

      expect(
        container.read(homeserverProvider).value,
        ServerChoice(
          officialHomeserver,
          apiHost: officialHomeserver,
          mailsSignUpCodes: false,
        ),
      );
      expect(client.homeserver, before);
    },
  );

  test('another server works even when zuno.chat is down', () async {
    final (container, client) = setUpContainer(down: {'zuno.chat'});
    await expectLater(
      container.read(homeserverProvider.future),
      throwsA(isA<http.ClientException>()),
    );

    await container.read(homeserverProvider.notifier).use(example);

    expect(
      container.read(homeserverProvider).value,
      ServerChoice(example, apiHost: example, mailsSignUpCodes: false),
    );
    expect(client.homeserver?.host, 'example.org');
  });

  test('a server whose address points sign-in at http is refused before '
      'anything reaches it', () async {
    final previous = HttpOverrides.current;
    addTearDown(() => HttpOverrides.global = previous);
    await installAppHttpOverrides(version: () async => '1.2.0');
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(listener.close);
    var accepted = 0;
    listener.listen((socket) {
      accepted++;
      socket.destroy();
    });
    final network = IOClient(HttpClient());
    addTearDown(network.close);
    final client = buildTestClient(
      httpClient: FakeHttpClient((request) async {
        final url = request.url;
        if (url.isScheme('http')) return network.get(url);
        if (url.host == 'example.org' && url.path == discoveryPath) {
          return http.Response(
            jsonEncode({
              'm.homeserver': {'base_url': 'http://127.0.0.1:${listener.port}'},
            }),
            200,
          );
        }
        if (url.path.endsWith('/versions')) {
          return http.Response(
            jsonEncode({
              'versions': ['v1.5'],
            }),
            200,
          );
        }
        return notFound();
      }),
    );
    final container = ProviderContainer(
      overrides: [matrixClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    await container.read(homeserverProvider.future);

    await expectLater(
      container.read(homeserverProvider.notifier).use(example),
      throwsA(isA<CleartextRefusedException>()),
    );

    expect(
      container.read(homeserverProvider).value,
      ServerChoice(
        officialHomeserver,
        apiHost: officialHomeserver,
        mailsSignUpCodes: false,
      ),
    );
    expect(client.homeserver?.host, 'zuno.chat');
    expect(accepted, 0);
  });

  test(
    'the discovery file is read once and the SDK does not read it again',
    () async {
      final (container, _) = setUpContainer(versions: const ['v1.5', 'v1.15']);

      await container.read(homeserverProvider.future);
      expect(requestsTo(discoveryPath), [
        Uri.parse('https://zuno.chat$discoveryPath'),
      ]);

      await container.read(homeserverProvider.notifier).use(example);
      expect(requestsTo(discoveryPath), [
        Uri.parse('https://zuno.chat$discoveryPath'),
        Uri.parse('https://example.org$discoveryPath'),
      ]);
      expect(requestsTo('/_matrix/client/v1/auth_metadata'), isEmpty);
    },
  );

  test('the announcement is carried in the choice', () async {
    final (container, client) = setUpContainer(
      discovery: (_) async => announcing('https://matrix.zuno.chat'),
      register: (_) async => codeSignUp(),
    );

    expect(
      await container.read(homeserverProvider.future),
      ServerChoice(
        officialHomeserver,
        apiHost: Uri.parse('https://matrix.zuno.chat'),
        mailsSignUpCodes: true,
      ),
    );
    expect(client.homeserver, Uri.parse('https://matrix.zuno.chat'));
    expect(await askSignUp(container), SignUpPath.emailedCode);
    expect(requestsTo(discoveryPath), hasLength(1));
  });

  test('an odd discovery failure is reported and the typed server is the '
      'API host', () async {
    final (container, client) = setUpContainer(
      discovery: (_) async => throw Exception('closed'),
    );

    late ServerChoice choice;
    final reports = await reportsDuring(
      () async => choice = await container.read(homeserverProvider.future),
    );

    expect(
      choice,
      ServerChoice(
        officialHomeserver,
        apiHost: officialHomeserver,
        mailsSignUpCodes: null,
      ),
    );
    expect(client.homeserver, officialHomeserver);
    expect(reports, ['read discovery file']);
  });

  test('a web page served as the discovery file leaves the typed server as '
      'the API host', () async {
    final (container, client) = setUpContainer(
      discovery: (_) async =>
          http.Response('<html><body>Welcome</body></html>', 200),
    );
    await container.read(homeserverProvider.future);

    await container.read(homeserverProvider.notifier).use(example);

    expect(
      container.read(homeserverProvider).value,
      ServerChoice(example, apiHost: example, mailsSignUpCodes: false),
    );
    expect(client.homeserver, example);
  });

  test(
    'a code from a server announcing nothing comes from its admin',
    () async {
      final (container, _) = setUpContainer(
        register: (_) async => codeSignUp(),
      );

      expect(await askSignUp(container), SignUpPath.adminCode);
      expect(requestsTo(discoveryPath), hasLength(1));
    },
  );

  test('the sign-up probe runs once per server choice', () async {
    final (container, _) = setUpContainer(register: (_) async => openSignUp());
    final choice = await container.read(homeserverProvider.future);
    container.listen(signUpPathProvider(choice), (_, _) {});

    expect(
      await container.read(signUpPathProvider(choice).future),
      SignUpPath.open,
    );
    expect(
      await container.read(
        signUpPathProvider(
          ServerChoice(
            officialHomeserver,
            apiHost: officialHomeserver,
            mailsSignUpCodes: false,
          ),
        ).future,
      ),
      SignUpPath.open,
    );

    expect(requestsTo(registerPath), hasLength(1));
  });

  test('an answer is asked afresh once nothing listens', () async {
    final (container, _) = setUpContainer(register: (_) async => openSignUp());
    final choice = await container.read(homeserverProvider.future);
    final listening = container.listen(signUpPathProvider(choice), (_, _) {});
    expect(
      await container.read(signUpPathProvider(choice).future),
      SignUpPath.open,
    );

    listening.close();
    await container.pump();

    expect(await askSignUp(container, choice), SignUpPath.open);
    expect(requestsTo(registerPath), hasLength(2));
  });

  test('a new server gets its own sign-up answer', () async {
    final (container, _) = setUpContainer(
      register: (request) async =>
          request.url.host == 'zuno.chat' ? openSignUp() : closedSignUp(),
    );
    final zuno = await container.read(homeserverProvider.future);
    expect(await askSignUp(container, zuno), SignUpPath.open);

    await container.read(homeserverProvider.notifier).use(example);
    final other = container.read(homeserverProvider).requireValue;

    expect(await askSignUp(container, other), SignUpPath.closed);
    expect(container.read(signUpPathProvider(zuno)).value, SignUpPath.open);
    expect(requestsTo(registerPath).map((url) => url.host), [
      'zuno.chat',
      'example.org',
    ]);
  });

  test('a probe answer for the previous server never shows', () async {
    final held = Completer<http.Response>();
    final probing = Completer<void>();
    final (container, _) = setUpContainer(
      register: (request) {
        if (request.url.host != 'zuno.chat') return Future.value(openSignUp());
        probing.complete();
        return held.future;
      },
    );
    final zuno = await container.read(homeserverProvider.future);
    container.listen(signUpPathProvider(zuno), (_, _) {});
    await probing.future;

    await container.read(homeserverProvider.notifier).use(example);
    final other = container.read(homeserverProvider).requireValue;
    final shown = <SignUpPath?>[];
    container.listen(
      signUpPathProvider(other),
      (_, next) => shown.add(next.value),
      fireImmediately: true,
    );
    expect(
      await container.read(signUpPathProvider(other).future),
      SignUpPath.open,
    );
    held.complete(closedSignUp());
    await pumpEventQueue();

    expect(container.read(signUpPathProvider(zuno)).value, SignUpPath.closed);
    expect(container.read(signUpPathProvider(other)).value, SignUpPath.open);
    expect(shown, [null, SignUpPath.open]);
  });

  test(
    'the probe goes to the chosen server while another is being checked',
    () async {
      final reached = Completer<void>();
      final candidate = Completer<http.Response>();
      final (container, client) = setUpContainer(
        versionsAt: {
          'typo.example': (_) {
            reached.complete();
            return candidate.future;
          },
        },
        register: (_) async => openSignUp(),
      );
      final zuno = await container.read(homeserverProvider.future);
      expect(await askSignUp(container, zuno), SignUpPath.open);

      final checking = container
          .read(homeserverProvider.notifier)
          .use(Uri.parse('https://typo.example'));
      await reached.future;
      expect(client.homeserver?.host, 'typo.example');
      container.invalidate(signUpPathProvider(zuno));
      expect(
        await container.read(signUpPathProvider(zuno).future),
        SignUpPath.open,
      );
      candidate.completeError(http.ClientException('offline'));
      await expectLater(checking, throwsA(isA<http.ClientException>()));

      expect(requestsTo(registerPath).map((url) => url.host), [
        'zuno.chat',
        'zuno.chat',
      ]);
      expect(client.homeserver?.host, 'zuno.chat');
    },
  );

  test('an inconclusive answer is asked again once invalidated', () async {
    var probes = 0;
    final (container, _) = setUpContainer(
      register: (_) async =>
          ++probes == 1 ? http.Response('', 503) : openSignUp(),
    );

    final choice = await container.read(homeserverProvider.future);
    expect(await askSignUp(container, choice), SignUpPath.unknown);
    container.invalidate(signUpPathProvider(choice));
    expect(
      await container.read(signUpPathProvider(choice).future),
      SignUpPath.open,
    );

    expect(probes, 2);
    expect(requestsTo('/_matrix/client/versions'), hasLength(1));
  });

  test(
    'an unreadable announcement is read again when a code is needed',
    () async {
      var discoveries = 0;
      final (container, _) = setUpContainer(
        discovery: (_) async {
          if (++discoveries == 1) throw http.ClientException('offline');
          return announcing('https://zuno.chat');
        },
        register: (_) async => codeSignUp(),
      );

      expect(
        await container.read(homeserverProvider.future),
        ServerChoice(
          officialHomeserver,
          apiHost: officialHomeserver,
          mailsSignUpCodes: null,
        ),
      );
      expect(await askSignUp(container), SignUpPath.emailedCode);
      expect(discoveries, 2);
    },
  );

  test(
    'an announcement still unreadable leaves the sign-up path unknown',
    () async {
      final (container, _) = setUpContainer(
        discovery: (_) async => throw http.ClientException('offline'),
        register: (_) async => codeSignUp(),
      );

      expect(await askSignUp(container), SignUpPath.unknown);
      expect(requestsTo(discoveryPath), hasLength(2));
    },
  );

  test('sign-in still works when the probe fails', () async {
    final (container, _) = setUpContainer(
      register: (_) async => throw http.ClientException('offline'),
    );

    expect(await askSignUp(container), SignUpPath.unknown);
    expect(
      container.read(homeserverProvider).value,
      ServerChoice(
        officialHomeserver,
        apiHost: officialHomeserver,
        mailsSignUpCodes: false,
      ),
    );
  });
}
