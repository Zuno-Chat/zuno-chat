import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../errors/caught_errors.dart';
import 'matrix_client_provider.dart';
import 'registration_support.dart';
import 'server_choice.dart';

final officialHomeserver = Uri.parse('https://zuno.chat');

final homeserverProvider =
    AsyncNotifierProvider<HomeserverNotifier, ServerChoice>(
      HomeserverNotifier.new,
      retry: (_, _) => null,
    );

class HomeserverNotifier extends AsyncNotifier<ServerChoice> {
  @override
  FutureOr<ServerChoice> build() => reportFailureOf(
    _check(ref.watch(matrixClientProvider), officialHomeserver),
    label: 'homeserver check',
  );

  Future<void> use(Uri homeserver) async {
    final client = ref.read(matrixClientProvider);
    final previous = client.homeserver;
    final ServerChoice choice;
    try {
      choice = await _check(client, homeserver);
    } catch (_) {
      client.homeserver = previous;
      rethrow;
    }
    state = AsyncData(choice);
  }
}

Future<ServerChoice> _check(Client client, Uri homeserver) async {
  final discovered = await readDiscovery(client, homeserver);
  await client.checkHomeserver(
    discovered.homeserver ?? homeserver,
    checkWellKnown: false,
    fetchAuthMetadata: false,
  );
  return ServerChoice(
    homeserver,
    apiHost: client.homeserver!,
    mailsSignUpCodes: discovered.mailsSignUpCodes,
  );
}

final signUpPathProvider = FutureProvider.autoDispose
    .family<SignUpPath, ServerChoice>((ref, choice) async {
      final client = ref.watch(matrixClientProvider);
      final support = await fetchRegistrationSupport(client, choice.apiHost);
      var mailsSignUpCodes = choice.mailsSignUpCodes;
      if (mailsSignUpCodes == null && support.requiresRegistrationToken) {
        final discovered = await readDiscovery(client, choice.homeserver);
        mailsSignUpCodes = discovered.mailsSignUpCodes;
      }
      return signUpPathFrom(support, mailsSignUpCodes: mailsSignUpCodes);
    }, retry: (_, _) => null);
