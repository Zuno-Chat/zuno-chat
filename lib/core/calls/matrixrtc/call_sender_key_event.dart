import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

const callSenderKeyEventType = 'im.zuno.call.sender_key';

const senderKeyLength = 32;

Uint8List randomSenderKey() {
  final random = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(senderKeyLength, (_) => random.nextInt(256)),
  );
}

typedef SenderKey = ({int epoch, int gen, Uint8List key});

typedef SenderKeyMark = ({int epoch, int gen});

SenderKeyMark markOf(SenderKey key) => (epoch: key.epoch, gen: key.gen);

Map<String, Object?> buildSenderKeyContent({
  required String callId,
  required SenderKey key,
}) => {
  'call_id': callId,
  'epoch': key.epoch,
  'gen': key.gen,
  'key': base64Encode(key.key),
};

SenderKey? parseSenderKeyContent(
  Map<String, Object?> content, {
  required String callId,
}) {
  if (content
      case {
        'call_id': final String id,
        'epoch': final int epoch,
        'gen': final int gen,
        'key': final String encoded,
      }
      when id == callId && epoch >= 0 && gen >= 1) {
    final key = _decode(encoded);
    if (key != null) return (epoch: epoch, gen: gen, key: key);
  }
  return null;
}

Uint8List? _decode(String encoded) {
  try {
    final key = base64Decode(encoded);
    return key.length == senderKeyLength ? key : null;
  } on FormatException {
    return null;
  }
}
