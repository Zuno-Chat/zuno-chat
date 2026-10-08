import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/push/voip/voip_registration.dart';

class FakeVoipRegistration extends VoipRegistration {
  final stateValue = ValueNotifier(VoipRegistrationState.idle);
  final refusalValue = ValueNotifier<VoipRefusal?>(null);
  final registered = <Client>[];

  @override
  ValueListenable<VoipRegistrationState> get state => stateValue;

  @override
  ValueListenable<VoipRefusal?> get lastRefusal => refusalValue;

  @override
  Future<void> registerNow(Client client) async => registered.add(client);
}
