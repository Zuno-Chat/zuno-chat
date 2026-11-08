import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/module/call_provider_discovery.dart';
import 'package:zuno/core/calls/module/calls_offer_provider.dart';
import 'package:zuno/core/matrix/client/matrix_client_provider.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  test('callsOfferProvider emits the persisted answer first', () async {
    final database = CachingFakeDatabaseApi();
    final client = buildTestClient(
      userId: '@me:example.org',
      database: database,
    );
    database.cache['zuno.calls_offer'] = (
      content: {
        'user_id': '@me:example.org',
        'saved_at': DateTime(2026, 11, 7).millisecondsSinceEpoch,
        'offer': 'none',
      },
      savedAt: DateTime(2026, 11, 7),
    );
    final container = ProviderContainer(
      overrides: [matrixClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    final seen = <CallsOffer?>[];
    container.listen(callsOfferProvider, (_, next) {
      if (next.hasValue) seen.add(next.value);
    });
    await pumpEventQueue();
    expect(seen, [CallsOffer.none]);
  });

  test('callsOfferedProvider stays true for a provider', () async {
    final container = ProviderContainer(
      overrides: [
        callsOfferProvider.overrideWith(
          (ref) => Stream.value(CallsOffer.cloudflare),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(callsOfferedProvider, (_, _) {});
    await pumpEventQueue();
    expect(container.read(callsOfferedProvider), isTrue);
  });

  test(
    'callsOfferedProvider is false only once the server says none',
    () async {
      final container = ProviderContainer(
        overrides: [
          callsOfferProvider.overrideWith(
            (ref) => Stream.value(CallsOffer.none),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(callsOfferedProvider), isTrue);
      container.listen(callsOfferedProvider, (_, _) {});
      await pumpEventQueue();
      expect(container.read(callsOfferedProvider), isFalse);
    },
  );
}
