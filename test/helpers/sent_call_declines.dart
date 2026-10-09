import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';

class SentCallDeclines {
  final _watchers = <List<String?>>[];

  void record(http.Request request) {
    if (request.method != 'PUT' || !request.url.path.contains('/send/')) return;
    final content = jsonDecode(request.body);
    if (content is! Map || content['msgtype'] != callDeclineMsgtype) return;
    for (final watcher in _watchers) {
      watcher.add(content['call_id'] as String?);
    }
  }

  List<String?> watch() {
    final declined = <String?>[];
    _watchers.add(declined);
    return declined;
  }
}
