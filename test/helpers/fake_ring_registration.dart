import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/push/ring/ring_registration.dart';

class FakeRingRegistration extends RingRegistration {
  final stateValue = ValueNotifier(RingRegistrationState.idle);
  final refusalValue = ValueNotifier<RingRefusal?>(null);
  final registered = <Client>[];
  final started = <Client>[];
  final followed = <Client>[];
  final forgotten = <Client>[];

  @override
  ValueListenable<RingRegistrationState> get state => stateValue;

  @override
  ValueListenable<RingRefusal?> get lastRefusal => refusalValue;

  @override
  Future<void> registerNow(Client client) async => registered.add(client);

  @override
  Future<void> start(Client client) async => started.add(client);

  @override
  Future<void> followToken(Client client) async => followed.add(client);

  @override
  Future<void> forget(Client client) async => forgotten.add(client);
}
