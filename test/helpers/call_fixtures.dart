import 'dart:typed_data';

import 'package:zuno/core/calls/call_engine.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';

const ann = VoipParticipantId(userId: '@ann:example.org', deviceId: 'ANN');
const bob = VoipParticipantId(userId: '@bob:example.org', deviceId: 'BOB');

Uint8List keyBytes() => Uint8List.fromList(List<int>.generate(32, (i) => i));

Future<void> keyEveryone(CallEngine engine) async {
  await engine.setOwnKey(1, keyBytes());
  await engine.sendWithSlot(1);
  for (final peer in const [ann, bob]) {
    await engine.setPeerKey(peer, 1, keyBytes());
  }
}
