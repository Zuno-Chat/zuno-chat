import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/media/voice/voice_recording.dart';

typedef _Chat = (String?, String);

class Unsent {
  final _texts = <_Chat, String>{};
  final _voices = <_Chat, VoiceClip>{};

  String textOf(Room room) => _texts[_chat(room)] ?? '';

  void keepText(Room room, String text) {
    if (text.trim().isEmpty) {
      _texts.remove(_chat(room));
    } else {
      _texts[_chat(room)] = text;
    }
  }

  VoiceClip? voiceOf(Room room) => _voices[_chat(room)];

  void keepVoice(Room room, VoiceClip? clip) {
    if (clip == null) {
      _voices.remove(_chat(room));
    } else {
      _voices[_chat(room)] = clip;
    }
  }

  _Chat _chat(Room room) => (room.client.userID, room.id);
}

final unsentProvider = Provider((ref) => Unsent());
