import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/push/voip/voip_registration.dart';

class FakeVoipRegistration extends VoipRegistration {
  final stateValue = ValueNotifier(VoipRegistrationState.idle);
  final registered = <Client>[];

  @override
  ValueListenable<VoipRegistrationState> get state => stateValue;

  @override
  Future<void> registerNow(Client client) async => registered.add(client);
}
