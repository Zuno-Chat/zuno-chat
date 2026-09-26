import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/voice_message.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Room room;

  setUp(() => room = buildTestRoom(buildTestClient()));

  Event audio(Map<String, Object?> extra) => buildTestEvent(
    room,
    eventId: r'$voice',
    senderId: '@bob:example.org',
    content: {'msgtype': MessageTypes.Audio, 'body': 'voice.ogg', ...extra},
  );

  group('isVoiceMessage', () {
    test('an audio message flagged as voice is one', () {
      expect(
        isVoiceMessage(
          audio({'org.matrix.msc3245.voice': <String, Object?>{}}),
        ),
        isTrue,
      );
    });

    test('plain audio is not', () {
      expect(isVoiceMessage(audio({})), isFalse);
    });

    test('a voice flag on anything but audio is ignored', () {
      final text = buildTestEvent(
        room,
        eventId: r'$text',
        senderId: '@bob:example.org',
        content: {
          'msgtype': MessageTypes.Text,
          'body': 'hi',
          'org.matrix.msc3245.voice': <String, Object?>{},
        },
      );
      expect(isVoiceMessage(text), isFalse);
    });
  });

  group('voiceMessageDuration', () {
    test('prefers the voice-message duration', () {
      final event = audio({
        'org.matrix.msc1767.audio': {'duration': 4200},
        'info': {'duration': 9999},
      });
      expect(voiceMessageDuration(event), const Duration(milliseconds: 4200));
    });

    test('falls back to the file info', () {
      final event = audio({
        'info': {'duration': 1500},
      });
      expect(voiceMessageDuration(event), const Duration(milliseconds: 1500));
    });

    test('is unknown when neither says', () {
      expect(voiceMessageDuration(audio({})), isNull);
    });
  });

  group('voiceMessageWaveform', () {
    test('reads the bars as whole numbers', () {
      final event = audio({
        'org.matrix.msc1767.audio': {
          'waveform': [0, 512.7, 1024],
        },
      });
      expect(voiceMessageWaveform(event), [0, 512, 1024]);
    });

    test('is none when missing or empty', () {
      expect(voiceMessageWaveform(audio({})), isNull);
      expect(
        voiceMessageWaveform(
          audio({
            'org.matrix.msc1767.audio': {'waveform': <int>[]},
          }),
        ),
        isNull,
      );
    });
  });
}
