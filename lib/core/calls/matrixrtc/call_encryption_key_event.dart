import 'dart:convert';
import 'dart:typed_data';

const callEncryptionKeyEventType = 'im.zuno.call.encryption_key';

Map<String, Object?> buildCallEncryptionKeyContent({
  required String callId,
  required Uint8List key,
}) => {'call_id': callId, 'key': base64Encode(key)};

Uint8List? parseCallEncryptionKeyContent({
  required Map<String, Object?> content,
  required String callId,
}) {
  if (content['call_id'] != callId) return null;
  final encoded = content['key'];
  if (encoded is! String) return null;
  try {
    return base64Decode(encoded);
  } on FormatException {
    return null;
  }
}
