import 'package:http/http.dart' as http;

const connectDeadline = Duration(seconds: 10);

class HttpDeadlines {
  const HttpDeadlines({this.thinkTime, this.idle});

  final Duration? thinkTime;
  final Duration? idle;
}

final class DeadlineRequest extends http.Request with http.Abortable {
  DeadlineRequest(super.method, super.url, {this.abortTrigger, this.thinkTime});

  @override
  final Future<void>? abortTrigger;

  final Duration? thinkTime;
}
