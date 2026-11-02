import 'dart:convert';

import '../models/call_quality.dart';

const qualityChannelName = 'quality';

final _tiers = CallQuality.values.asNameMap();

String encodeQualityReport(CallQuality quality) =>
    jsonEncode({'quality': quality.name});

CallQuality? decodeQualityReport(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (json case {'quality': final String name}) {
    return _tiers[name];
  }
  return null;
}
