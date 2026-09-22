import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/homeserver.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/server_name.dart';

import '../../helpers/fake_matrix.dart';
import '../../helpers/fixed_homeserver.dart';

void main() {
  Client delegatedClient({String? userId}) =>
      buildTestClient(userId: userId)
        ..homeserver = Uri.parse('https://matrix.example.org');

  ProviderContainer containerFor(Client client, {FutureOr<Uri>? chosen}) {
    final container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        homeserverProvider.overrideWith(
          () => FixedHomeserver(chosen ?? Completer<Uri>().future),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('the account domain is the server name, not the delegated API host', () {
    final client = delegatedClient(userId: '@alice:zuno.chat');

    expect(ownServerName(client), 'zuno.chat');
  });

  test('without an account there is no server name to read off it', () {
    expect(ownServerName(delegatedClient()), isNull);
  });

  test('before logging in the chosen server wins over the API host', () {
    final container = containerFor(
      delegatedClient(),
      chosen: Uri.parse('https://zuno.chat'),
    );

    expect(container.read(serverNameProvider), 'zuno.chat');
  });

  test('once logged in the account domain wins over the chosen server', () {
    final container = containerFor(
      delegatedClient(userId: '@alice:zuno.chat'),
      chosen: Uri.parse('https://typo.example'),
    );

    expect(container.read(serverNameProvider), 'zuno.chat');
  });

  test('while the server is still being checked, the homeserver host', () {
    final container = containerFor(delegatedClient());

    expect(container.read(serverNameProvider), 'matrix.example.org');
  });

  test('no homeserver and no account means no server name at all', () {
    expect(containerFor(buildTestClient()).read(serverNameProvider), isNull);
  });
}
