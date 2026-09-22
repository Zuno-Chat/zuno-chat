import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'matrix_client_provider.dart';

final officialHomeserver = Uri.parse('https://zuno.chat');

final homeserverProvider = AsyncNotifierProvider<HomeserverNotifier, Uri>(
  HomeserverNotifier.new,
  retry: (_, _) => null,
);

class HomeserverNotifier extends AsyncNotifier<Uri> {
  @override
  FutureOr<Uri> build() async {
    await ref.watch(matrixClientProvider).checkHomeserver(officialHomeserver);
    return officialHomeserver;
  }

  Future<void> use(Uri homeserver) async {
    final client = ref.read(matrixClientProvider);
    final previous = client.homeserver;
    try {
      await client.checkHomeserver(homeserver);
    } catch (_) {
      client.homeserver = previous;
      rethrow;
    }
    state = AsyncData(homeserver);
  }
}
