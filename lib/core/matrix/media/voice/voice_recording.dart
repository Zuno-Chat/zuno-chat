import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../../../async/background_work.dart';
import '../../../files/file_system.dart';
import '../../../files/unique_name.dart';
import '../../../platform/platform_capabilities.dart';
import 'ogg_opus_from_caf.dart';

typedef VoiceClip = ({Uint8List bytes, Duration duration, List<int> waveform});

typedef VoiceRecordingSetup = ({
  RecordConfig config,
  String extension,
  Future<Uint8List?> Function(Uint8List recorded) toOggOpus,
});

const _voiceConfig = RecordConfig(
  encoder: AudioEncoder.opus,
  bitRate: 32000,
  sampleRate: 48000,
  numChannels: 1,
);

VoiceRecordingSetup voiceRecordingSetup(PlatformCapabilities capabilities) =>
    capabilities.recorderWritesOgg
    ? (
        config: _voiceConfig,
        extension: 'ogg',
        toOggOpus: (recorded) async => recorded,
      )
    : (config: _voiceConfig, extension: 'caf', toOggOpus: _oggOpusFromCaf);

Future<Uint8List?> _oggOpusFromCaf(Uint8List recorded) => runInBackground(
  () => oggOpusFromCaf(recorded),
  debugName: 'repackage voice as Ogg',
);

Future<String> newVoiceFilePath(String extension) async => p.join(
  (await temporaryDirectory()).path,
  'voice-${uniqueName()}.$extension',
);

String? sniffAudioMimeType(Uint8List bytes) {
  bool startsWith(List<int> prefix, [int at = 0]) {
    if (bytes.length < at + prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[at + i] != prefix[i]) return false;
    }
    return true;
  }

  if (startsWith('OggS'.codeUnits)) return 'audio/ogg';
  if (startsWith('ftyp'.codeUnits, 4)) return 'audio/mp4';
  if (startsWith('ID3'.codeUnits)) return 'audio/mpeg';
  if (bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xf6) == 0xf0) {
    return 'audio/aac';
  }
  if (bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0) {
    return 'audio/mpeg';
  }
  if (startsWith('RIFF'.codeUnits) && startsWith('WAVE'.codeUnits, 8)) {
    return 'audio/wav';
  }
  return null;
}
