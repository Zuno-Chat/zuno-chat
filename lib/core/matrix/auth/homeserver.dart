import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../errors/caught_errors.dart';
import '../client/matrix_client_provider.dart';
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
  FutureOr<ServerChoice> build() async {
    final client = ref.watch(matrixClientProvider);
    final choice = await reportFailureOf(
      checkServer(client, officialHomeserver),
      label: 'homeserver check',
    );
    return _pointed(client, choice);
  }

  void adopt(ServerChoice choice) =>
      state = AsyncData(_pointed(ref.read(matrixClientProvider), choice));
}

ServerChoice _pointed(Client client, ServerChoice choice) {
  client.homeserver = choice.apiHost;
  return choice;
}

final signUpPathProvider = FutureProvider.autoDispose
    .family<SignUpPath, ServerChoice>(
      (ref, choice) async => switch (choice.signIn) {
        OAuthSignIn(canCreateAccount: true) => SignUpPath.oauth,
        OAuthSignIn() => SignUpPath.closed,
        PasswordSignIn() => signUpPathFrom(
          await fetchRegistrationSupport(
            ref.watch(matrixClientProvider),
            choice.apiHost,
          ),
        ),
      },
      retry: (_, _) => null,
    );
