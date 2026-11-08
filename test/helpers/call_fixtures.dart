import 'dart:typed_data';

import 'package:zuno/core/calls/models/voip_participant_id.dart';

const ann = VoipParticipantId(userId: '@ann:example.org', deviceId: 'ANN');
const bob = VoipParticipantId(userId: '@bob:example.org', deviceId: 'BOB');

Uint8List callKey() => Uint8List.fromList(List<int>.generate(32, (i) => i));
