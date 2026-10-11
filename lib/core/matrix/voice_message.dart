import 'package:matrix/matrix.dart';

bool isVoiceMessage(Event event) =>
    event.messageType == MessageTypes.Audio &&
    event.content.containsKey('org.matrix.msc3245.voice');

Duration? voiceMessageDuration(Event event) {
  final ms =
      event.content
          .tryGetMap<String, dynamic>('org.matrix.msc1767.audio')
          ?.tryGet<int>('duration') ??
      event.infoMap.tryGet<int>('duration');
  return ms == null ? null : Duration(milliseconds: ms);
}

List<int>? voiceMessageWaveform(Event event) {
  final raw = event.content
      .tryGetMap<String, dynamic>('org.matrix.msc1767.audio')
      ?.tryGetList<Object?>('waveform');
  final bars = [
    for (final value in raw ?? const <Object?>[])
      if (value is num && value.isFinite) value.toInt().clamp(0, 1024),
  ];
  return bars.isEmpty ? null : bars;
}
