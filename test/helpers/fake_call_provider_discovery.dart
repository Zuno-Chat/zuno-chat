import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:zuno/core/calls/module/call_provider_discovery.dart';
import 'package:zuno/core/calls/module/calls_offer_provider.dart';

Override fakeCallDiscoveryOverride() => callProviderDiscoveryProvider
    .overrideWith((ref) => FakeCallProviderDiscovery());

FakeCallProviderDiscovery fakeDiscoveryIn(ProviderContainer container) =>
    container.read(callProviderDiscoveryProvider) as FakeCallProviderDiscovery;

class FakeCallProviderDiscovery implements CallProviderDiscovery {
  FakeCallProviderDiscovery([this._offer = CallsOffer.cloudflare]);

  CallsOffer? _offer;
  final _changes = StreamController<CallsOffer?>.broadcast();
  Object? error;
  int currentCalls = 0;
  int refetchCalls = 0;
  int staleChecks = 0;

  set offer(CallsOffer? value) {
    _offer = value;
    _changes.add(value);
  }

  @override
  Stream<CallsOffer?> get offers {
    late final StreamController<CallsOffer?> controller;
    StreamSubscription<CallsOffer?>? changes;
    controller = StreamController<CallsOffer?>(
      onListen: () {
        changes = _changes.stream.listen(controller.add);
        controller.add(_offer);
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<CallsOffer> current() async {
    currentCalls++;
    return _answer();
  }

  @override
  Future<CallsOffer> refetch() async {
    refetchCalls++;
    return _answer();
  }

  @override
  Future<void> refreshIfStale() async => staleChecks++;

  @override
  void dispose() => unawaited(_changes.close());

  CallsOffer _answer() {
    if (error case final failure?) throw failure;
    return _offer ?? CallsOffer.cloudflare;
  }
}
