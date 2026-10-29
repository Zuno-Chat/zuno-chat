import 'call_quality_policy.dart';

const _opusParams = {'useinbandfec': '1', 'usedtx': '0'};
const _videoParams = {'x-google-start-bitrate': '$startBitrateKbps'};
const _videoHelpers = {'rtx', 'red', 'ulpfec', 'flexfec-03'};
const _directionsWeDontSend = {'a=sendonly', 'a=inactive'};

final _rtpmap = RegExp(r'^a=rtpmap:(\d+) ([^/]+)/');
final _fmtp = RegExp(r'^a=fmtp:(\d+)(?: (.*))?$');

String withSendParams(String sdp) {
  final eol = sdp.contains('\r\n') ? '\r\n' : '\n';
  final tuned = <String>[];
  var section = <String>[];
  for (final line in sdp.split(eol)) {
    if (line.startsWith('m=')) {
      tuned.addAll(_tuneSection(section));
      section = [];
    }
    section.add(line);
  }
  tuned.addAll(_tuneSection(section));
  return tuned.join(eol);
}

List<String> _tuneSection(List<String> lines) {
  final video =
      (lines.firstOrNull?.startsWith('m=video') ?? false) &&
      !lines.any(_directionsWeDontSend.contains);
  final params = <String, Map<String, String>>{
    for (final line in lines)
      if (_rtpmap.firstMatch(line) case final rtpmap?)
        rtpmap.group(1)!: ?_paramsFor(rtpmap.group(2)!, video: video),
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

Map<String, String>? _paramsFor(String codec, {required bool video}) {
  final name = codec.toLowerCase();
  if (name == 'opus') return _opusParams;
  if (video && !_videoHelpers.contains(name)) return _videoParams;
  return null;
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
