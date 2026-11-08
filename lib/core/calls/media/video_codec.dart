import 'call_quality_policy.dart';

const sentVideoCodec = 'VP8';

final _rtpmap = RegExp(r'^a=rtpmap:(\d+) ([^/]+)/');

final _fmtp = RegExp(r'^a=fmtp:(\d+)(?: (.*))?$');

final _sentCodecName = sentVideoCodec.toLowerCase();

const _videoHelpers = {'rtx', 'red', 'ulpfec', 'flexfec-03'};
const _directionsWeDontSend = {'a=sendonly', 'a=inactive'};
const _startBitrate = {'x-google-start-bitrate': '$startBitrateKbps'};

String mapSdpSections(
  String sdp,
  List<String> Function(List<String> section) tune,
) {
  final eol = sdp.contains('\r\n') ? '\r\n' : '\n';
  final tuned = <String>[];
  var section = <String>[];
  for (final line in sdp.split(eol)) {
    if (line.startsWith('m=')) {
      tuned.addAll(tune(section));
      section = [];
    }
    section.add(line);
  }
  tuned.addAll(tune(section));
  return tuned.join(eol);
}

String withSentVideoParams(String sdp) =>
    mapSdpSections(sdp, withSentVideoSectionParams);

List<String> withSentVideoSectionParams(List<String> section) {
  final sendsVideo =
      (section.firstOrNull?.startsWith('m=video') ?? false) &&
      !section.any(_directionsWeDontSend.contains);
  if (!sendsVideo) return section;
  return _withSentVideoCodecFirst(
    withFmtpParams(
      section,
      (codec) =>
          _videoHelpers.contains(codec.toLowerCase()) ? null : _startBitrate,
    ),
  );
}

List<String> _withSentVideoCodecFirst(List<String> section) {
  final sent = {
    for (final line in section)
      if (_rtpmap.firstMatch(line) case final rtpmap?
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

List<String> withFmtpParams(
  List<String> lines,
  Map<String, String>? Function(String codec) paramsFor,
) {
  final params = <String, Map<String, String>>{
    for (final line in lines)
      if (_rtpmap.firstMatch(line) case final rtpmap?)
        rtpmap.group(1)!: ?paramsFor(rtpmap.group(2)!),
  };
  if (params.isEmpty) return lines;
  final described = {
    for (final line in lines) ?_fmtp.firstMatch(line)?.group(1),
  };
  final tuned = <String>[];
  for (final line in lines) {
    final fmtp = _fmtp.firstMatch(line);
    final fmtpParams = fmtp == null ? null : params[fmtp.group(1)];
    if (fmtpParams != null) {
      tuned.add(
        'a=fmtp:${fmtp!.group(1)} ${_merged(fmtp.group(2) ?? '', fmtpParams)}',
      );
      continue;
    }
    tuned.add(line);
    final pt = _rtpmap.firstMatch(line)?.group(1);
    final missing = pt == null || described.contains(pt) ? null : params[pt];
    if (missing != null) tuned.add('a=fmtp:$pt ${_merged('', missing)}');
  }
  return tuned;
}

String _merged(String params, Map<String, String> wanted) {
  final entries = [
    for (final part in params.split(';'))
      if (part.trim().isNotEmpty) part.trim(),
  ];
  for (final MapEntry(:key, :value) in wanted.entries) {
    final at = entries.indexWhere((e) => e.split('=').first == key);
    if (at == -1) {
      entries.add('$key=$value');
    } else {
      entries[at] = '$key=$value';
    }
  }
  return entries.join(';');
}
