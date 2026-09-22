import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/homeserver.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  final contacted = <String>[];

  setUp(contacted.clear);

  MockClient server({Set<String> down = const {}}) =>
      MockClient((request) async {
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
    expect(contacted, isNotEmpty);
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
}
