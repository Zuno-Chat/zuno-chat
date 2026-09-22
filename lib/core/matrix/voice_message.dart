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
  if (raw == null || raw.isEmpty) return null;
  return raw.map((v) => (v as num).toInt()).toList();
}
