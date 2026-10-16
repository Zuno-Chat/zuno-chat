import 'dart:convert';

int fnv1a32(String input) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(input)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

int messageNotificationIdFor(String roomId) => fnv1a32(roomId) & 0x7fffffff;
