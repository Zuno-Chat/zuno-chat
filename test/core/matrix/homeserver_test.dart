import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/homeserver.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/network/app_http_overrides.dart';

import '../../helpers/fake_http.dart';
import '../../helpers/fake_matrix.dart';

void main() {
  final contacted = <String>[];

  setUp(contacted.clear);

  FakeHttpClient server({Set<String> down = const {}}) =>
      FakeHttpClient((request) async {
        contacted.add(request.url.host);
        if (down.contains(request.url.host)) {
          throw http.ClientException('offline');
        }
        if (request.url.path.endsWith('/versions')) {
          return http.Response(
            jsonEncode({
              'versions': ['v1.1', 'v1.5'],
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'errcode': 'M_NOT_FOUND'}), 404);
      });

  (ProviderContainer, Client) setUpContainer({Set<String> down = const {}}) {
    final client = buildTestClient(httpClient: server(down: down));
    final container = ProviderContainer(
      overrides: [matrixClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    return (container, client);
  }

  test('zuno.chat is verified first, and nothing else is contacted', () async {
    final (container, client) = setUpContainer();

    final verified = await container.read(homeserverProvider.future);

    expect(verified, officialHomeserver);
    expect(client.homeserver?.host, 'zuno.chat');
    expect(contacted.toSet(), {'zuno.chat'});
  });

  test('a server that answers becomes the one to sign in to', () async {
    final (container, client) = setUpContainer();
    await container.read(homeserverProvider.future);

    await container
        .read(homeserverProvider.notifier)
        .use(Uri.parse('https://example.org'));

    expect(
      container.read(homeserverProvider).value,
      Uri.parse('https://example.org'),
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

      expect(container.read(homeserverProvider).value, officialHomeserver);
      expect(client.homeserver, before);
    },
  );

  test('another server works even when zuno.chat is down', () async {
    final (container, client) = setUpContainer(down: {'zuno.chat'});
    await expectLater(
      container.read(homeserverProvider.future),
      throwsA(isA<http.ClientException>()),
    );

    await container
        .read(homeserverProvider.notifier)
        .use(Uri.parse('https://example.org'));

    expect(
      container.read(homeserverProvider).value,
      Uri.parse('https://example.org'),
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
        if (url.host == 'example.org' &&
            url.path == '/.well-known/matrix/client') {
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
        return http.Response(jsonEncode({'errcode': 'M_NOT_FOUND'}), 404);
      }),
    );
    final container = ProviderContainer(
      overrides: [matrixClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    await container.read(homeserverProvider.future);

    await expectLater(
      container
          .read(homeserverProvider.notifier)
          .use(Uri.parse('https://example.org')),
      throwsA(isA<CleartextRefusedException>()),
    );

    expect(container.read(homeserverProvider).value, officialHomeserver);
    expect(client.homeserver?.host, 'zuno.chat');
    expect(accepted, 0);
  });
}
