import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

class UnsentText {
  final _texts = <(String?, String), String>{};

  String textOf(Room room) => _texts[_key(room)] ?? '';

  void keep(Room room, String text) {
    if (text.trim().isEmpty) {
      _texts.remove(_key(room));
    } else {
      _texts[_key(room)] = text;
    }
  }

  (String?, String) _key(Room room) => (room.client.userID, room.id);
}

final unsentTextProvider = Provider((ref) => UnsentText());
