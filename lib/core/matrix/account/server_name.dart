import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../auth/homeserver.dart';
import '../client/matrix_client_provider.dart';

String? ownServerName(Client client) => client.userID?.domain;

final serverNameProvider = Provider<String?>((ref) {
  final client = ref.watch(matrixClientProvider);
  return ownServerName(client) ??
      ref.watch(homeserverProvider).value?.homeserver.host ??
      client.homeserver?.host;
});
