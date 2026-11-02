const sentVideoCodec = 'VP8';

final sdpRtpmap = RegExp(r'^a=rtpmap:(\d+) ([^/]+)/');

final _sentCodecName = sentVideoCodec.toLowerCase();

List<String> withSentVideoCodecFirst(List<String> section) {
  final sent = {
    for (final line in section)
      if (sdpRtpmap.firstMatch(line) case final rtpmap?
          when rtpmap.group(2)!.toLowerCase() == _sentCodecName)
        rtpmap.group(1)!,
  };
  final mLine = section.firstOrNull?.split(' ');
  if (sent.isEmpty || mLine == null || mLine.length <= 3) return section;
  final payloads = mLine.sublist(3);
  return [
    [
      ...mLine.take(3),
      ...payloads.where(sent.contains),
      ...payloads.where((p) => !sent.contains(p)),
    ].join(' '),
    ...section.skip(1),
  ];
}
