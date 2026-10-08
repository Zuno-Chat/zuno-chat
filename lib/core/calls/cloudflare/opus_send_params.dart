const _sendParams = {'useinbandfec': '1', 'usedtx': '0'};

final _opusPayload = RegExp(r'^a=rtpmap:(\d+) opus/', caseSensitive: false);
final _fmtp = RegExp(r'^a=fmtp:(\d+)(?: (.*))?$');

String withOpusSendParams(String sdp) {
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
  final opus = {
    for (final line in lines) ?_opusPayload.firstMatch(line)?.group(1),
  };
  if (opus.isEmpty) return lines;
  final described = {
    for (final line in lines) ?_fmtp.firstMatch(line)?.group(1),
  };
  final tuned = <String>[];
  for (final line in lines) {
    final fmtp = _fmtp.firstMatch(line);
    if (fmtp != null && opus.contains(fmtp.group(1))) {
      tuned.add('a=fmtp:${fmtp.group(1)} ${_merged(fmtp.group(2) ?? '')}');
      continue;
    }
    tuned.add(line);
    final pt = _opusPayload.firstMatch(line)?.group(1);
    if (pt != null && !described.contains(pt)) {
      tuned.add('a=fmtp:$pt ${_merged('')}');
    }
  }
  return tuned;
}

String _merged(String params) {
  final entries = [
    for (final part in params.split(';'))
      if (part.trim().isNotEmpty) part.trim(),
  ];
  for (final MapEntry(:key, :value) in _sendParams.entries) {
    final at = entries.indexWhere((e) => e.split('=').first == key);
    if (at == -1) {
      entries.add('$key=$value');
    } else {
      entries[at] = '$key=$value';
    }
  }
  return entries.join(';');
}
