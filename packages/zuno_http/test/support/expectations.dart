import 'package:flutter_test/flutter_test.dart';
import 'package:zuno_http/zuno_http.dart';

const agent = 'Zuno/1.2.0 (Android; im.zuno.chat)';

const matrixDeadlines = HttpDeadlines();

const serviceDeadlines = HttpDeadlines(
  thinkTime: Duration(seconds: 30),
  idle: Duration(seconds: 30),
);

Matcher failsAs(HttpFailureKind kind) =>
    isA<NativeHttpException>().having((e) => e.kind, 'kind', kind);
