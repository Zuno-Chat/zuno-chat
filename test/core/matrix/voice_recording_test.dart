import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'package:zuno/core/matrix/voice_recording.dart';

import '../../helpers/platform_capabilities.dart';

void main() {
  group('where the recorder writes Ogg', () {
    final setup = voiceRecordingSetup(androidCapabilities);

    test('it records mono Opus at 48 kHz and 32 kbps into an .ogg file', () {
      expect(setup.extension, 'ogg');
      expect(setup.config.encoder, AudioEncoder.opus);
      expect(setup.config.sampleRate, 48000);
      expect(setup.config.numChannels, 1);
      expect(setup.config.bitRate, 32000);
    });

    test('it sends the recording untouched', () {
      final recorded = Uint8List.fromList([1, 2, 3]);

      expect(setup.toOggOpus(recorded), same(recorded));
    });
  });

  group('where the recorder cannot write Ogg', () {
    final setup = voiceRecordingSetup(iosCapabilities);

    test('it records mono Opus at 48 kHz and 32 kbps into a .caf file', () {
      expect(setup.extension, 'caf');
      expect(setup.config.encoder, AudioEncoder.opus);
      expect(setup.config.sampleRate, 48000);
      expect(setup.config.numChannels, 1);
      expect(setup.config.bitRate, 32000);
    });

    test('a recording it cannot repackage is not sent', () {
      expect(setup.toOggOpus(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  group('sniffAudioMimeType', () {
    Uint8List bytes(List<int> head) =>
        Uint8List.fromList([...head, 0, 0, 0, 0]);

    test('recognises the formats voice messages arrive in', () {
      expect(sniffAudioMimeType(bytes('OggS'.codeUnits)), 'audio/ogg');
      expect(
        sniffAudioMimeType(bytes([0, 0, 0, 0x20, ...'ftypM4A '.codeUnits])),
        'audio/mp4',
      );
      expect(sniffAudioMimeType(bytes('ID3'.codeUnits)), 'audio/mpeg');
      expect(sniffAudioMimeType(bytes([0xff, 0xfb])), 'audio/mpeg');
      expect(sniffAudioMimeType(bytes([0xff, 0xf1])), 'audio/aac');
      expect(sniffAudioMimeType(bytes([0xff, 0xf9])), 'audio/aac');
      expect(
        sniffAudioMimeType(
          bytes([...'RIFF'.codeUnits, 1, 2, 3, 4, ...'WAVE'.codeUnits]),
        ),
        'audio/wav',
      );
    });

    test('anything else stays unknown', () {
      expect(sniffAudioMimeType(bytes('hello'.codeUnits)), isNull);
      expect(sniffAudioMimeType(Uint8List(2)), isNull);
    });
  });
}
