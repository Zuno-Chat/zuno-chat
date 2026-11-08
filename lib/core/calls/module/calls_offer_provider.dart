import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../matrix/client/matrix_client_provider.dart';
import 'call_provider_discovery.dart';

final callProviderDiscoveryProvider = Provider<CallProviderDiscovery>((ref) {
  final discovery = CallProviderDiscovery(
    client: ref.watch(matrixClientProvider),
  );
  ref.onDispose(discovery.dispose);
  return discovery;
});

final callsOfferProvider = StreamProvider<CallsOffer?>(
  (ref) => ref.watch(callProviderDiscoveryProvider).offers,
);

final callsOfferedProvider = Provider<bool>(
  (ref) => ref.watch(callsOfferProvider).value != CallsOffer.none,
);
