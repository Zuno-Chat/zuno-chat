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
  final zuno = ServerChoice(officialHomeserver, apiHost: officialHomeserver);
  const discoveryPath = '/.well-known/matrix/client';
  const registerPath = '/_matrix/client/v3/register';

  setUp(requests.clear);

  List<Uri> requestsTo(String path) =>
      requests.where((url) => url.path == path).toList();

  http.Response notFound() =>
      http.Response(jsonEncode({'errcode': 'M_NOT_FOUND'}), 404);

  http.Response versionsAnswer(List<String> versions) =>
      http.Response(jsonEncode({'versions': versions}), 200);

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
          return versionsAnswer(versions);
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

  Future<void> useServer(
    ProviderContainer container,
    Client client,
    Uri server,
  ) async => container
      .read(homeserverProvider.notifier)
      .adopt(await checkServer(client, server));

  test('zuno.chat is checked first and adopted, and nothing else is '
      'contacted', () async {
    final (container, client) = setUpContainer();

    expect(await container.read(homeserverProvider.future), zuno);
    expect(client.homeserver, officialHomeserver);
    expect(requests.map((url) => url.host).toSet(), {'zuno.chat'});
  });

  test('the client points at zuno.chat only once its check passes', () async {
    final reached = Completer<void>();
    final answer = Completer<http.Response>();
    final (container, client) = setUpContainer(
      versionsAt: {
        'zuno.chat': (_) {
          reached.complete();
          return answer.future;
        },
      },
    );

    final checking = container.read(homeserverProvider.future);
    await reached.future;
    expect(client.homeserver, isNull);

    answer.complete(versionsAnswer(const ['v1.5']));
    expect(await checking, zuno);
    expect(client.homeserver, officialHomeserver);
  });

  test('a failed zuno.chat check is reported and points the client '
      'nowhere', () async {
    final (container, client) = setUpContainer(
      versionsAt: {'zuno.chat': (_) async => http.Response('', 500)},
    );

    final reports = await reportsDuring(
      () => expectLater(
        container.read(homeserverProvider.future),
        throwsException,
      ),
    );

    expect(reports, ['homeserver check']);
    expect(client.homeserver, isNull);
  });

  test('an adopted server becomes the one to sign in to', () async {
    final (container, client) = setUpContainer();
    await container.read(homeserverProvider.future);

    await useServer(container, client, example);

    expect(
      container.read(homeserverProvider).value,
      ServerChoice(example, apiHost: example),
    );
    expect(client.homeserver, example);
  });

  test('the client stays on the previous server while another is checked, '
      'and moves only once it is adopted', () async {
    final reached = Completer<void>();
    final answer = Completer<http.Response>();
    final (container, client) = setUpContainer(
      versionsAt: {
        'example.org': (_) {
          reached.complete();
          return answer.future;
        },
      },
    );
    await container.read(homeserverProvider.future);

    final checking = checkServer(client, example);
    await reached.future;
    expect(client.homeserver, officialHomeserver);

    answer.complete(versionsAnswer(const ['v1.5']));
    final choice = await checking;
    expect(client.homeserver, officialHomeserver);
    expect(container.read(homeserverProvider).value, zuno);

    container.read(homeserverProvider.notifier).adopt(choice);
    expect(client.homeserver, example);
  });

  test(
    'a server that does not answer leaves the previous one in place',
    () async {
      final (container, client) = setUpContainer(down: {'typo.example'});
      await container.read(homeserverProvider.future);

      await expectLater(
        checkServer(client, Uri.parse('https://typo.example')),
        throwsA(isA<http.ClientException>()),
      );

      expect(container.read(homeserverProvider).value, zuno);
      expect(client.homeserver, officialHomeserver);
    },
  );

  test('another server works even when zuno.chat is down', () async {
    final (container, client) = setUpContainer(down: {'zuno.chat'});
    await expectLater(
      container.read(homeserverProvider.future),
      throwsA(isA<http.ClientException>()),
    );
    expect(client.homeserver, isNull);

    await useServer(container, client, example);

    expect(
      container.read(homeserverProvider).value,
      ServerChoice(example, apiHost: example),
    );
    expect(client.homeserver, example);
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
          return versionsAnswer(const ['v1.5']);
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
      checkServer(client, example),
      throwsA(isA<CleartextRefusedException>()),
    );

    expect(container.read(homeserverProvider).value, zuno);
    expect(client.homeserver, officialHomeserver);
    expect(accepted, 0);
  });

  test(
    'each check reads the discovery file and the auth metadata once',
    () async {
      const metadataPath = '/_matrix/client/v1/auth_metadata';
      final (container, client) = setUpContainer(
        versions: const ['v1.5', 'v1.15'],
      );

      await container.read(homeserverProvider.future);
      expect(requestsTo(discoveryPath), [
        Uri.parse('https://zuno.chat$discoveryPath'),
      ]);
      expect(requestsTo(metadataPath), [
        Uri.parse('https://zuno.chat$metadataPath'),
      ]);

      await useServer(container, client, example);
      expect(requestsTo(discoveryPath), [
        Uri.parse('https://zuno.chat$discoveryPath'),
        Uri.parse('https://example.org$discoveryPath'),
      ]);
      expect(requestsTo(metadataPath), [
        Uri.parse('https://zuno.chat$metadataPath'),
        Uri.parse('https://example.org$metadataPath'),
      ]);
    },
  );

  test('the sign-up probe asks the API host the discovery file names, and '
      'never reads the file again', () async {
    final apiHost = Uri.parse('https://matrix.zuno.chat');
    final (container, client) = setUpContainer(
      discovery: (_) async => http.Response(
        jsonEncode({
          'm.homeserver': {'base_url': '$apiHost'},
        }),
        200,
      ),
      register: (_) async => codeSignUp(),
    );

    expect(
      await container.read(homeserverProvider.future),
      ServerChoice(officialHomeserver, apiHost: apiHost),
    );
    expect(client.homeserver, apiHost);
    expect(await askSignUp(container), SignUpPath.code);
    expect(requestsTo(registerPath).single.host, 'matrix.zuno.chat');
    expect(requestsTo(discoveryPath), hasLength(1));
  });

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
          ServerChoice(officialHomeserver, apiHost: officialHomeserver),
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
    final (container, client) = setUpContainer(
      register: (request) async =>
          request.url.host == 'zuno.chat' ? openSignUp() : closedSignUp(),
    );
    final zuno = await container.read(homeserverProvider.future);
    expect(await askSignUp(container, zuno), SignUpPath.open);

    await useServer(container, client, example);
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
    final (container, client) = setUpContainer(
      register: (request) {
        if (request.url.host != 'zuno.chat') return Future.value(openSignUp());
        probing.complete();
        return held.future;
      },
    );
    final zuno = await container.read(homeserverProvider.future);
    container.listen(signUpPathProvider(zuno), (_, _) {});
    await probing.future;

    await useServer(container, client, example);
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

      final checking = checkServer(client, Uri.parse('https://typo.example'));
      await reached.future;
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
      expect(client.homeserver, officialHomeserver);
    },
  );

  test('an OAuth choice answers its sign-up path without the probe', () async {
    final (container, _) = setUpContainer(register: (_) async => openSignUp());
    await container.read(homeserverProvider.future);

    for (final (canCreate, path) in [
      (true, SignUpPath.oauth),
      (false, SignUpPath.closed),
    ]) {
      final choice = ServerChoice(
        example,
        apiHost: example,
        signIn: OAuthSignIn(canCreateAccount: canCreate),
      );
      expect(await askSignUp(container, choice), path);
    }

    expect(requestsTo(registerPath), isEmpty);
  });

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

  test('sign-in still works when the probe fails', () async {
    final (container, _) = setUpContainer(
      register: (_) async => throw http.ClientException('offline'),
    );

    expect(await askSignUp(container), SignUpPath.unknown);
    expect(container.read(homeserverProvider).value, zuno);
  });
}
