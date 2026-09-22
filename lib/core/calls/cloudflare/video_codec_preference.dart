import 'package:flutter_webrtc/flutter_webrtc.dart';

List<RTCRtpCodecCapability> orderVideoCodecs(
  List<RTCRtpCodecCapability> codecs, {
  List<String> preferred = const ['video/VP8', 'video/H264'],
}) {
  int rank(RTCRtpCodecCapability codec) {
    final index = preferred.indexWhere(
      (mime) => mime.toLowerCase() == codec.mimeType.toLowerCase(),
    );
    return index < 0 ? preferred.length : index;
  }

  final indexed = codecs.indexed.toList()
    ..sort((a, b) {
      final byRank = rank(a.$2).compareTo(rank(b.$2));
      return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
    });
  return [for (final (_, codec) in indexed) codec];
}
