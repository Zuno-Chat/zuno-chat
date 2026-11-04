import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

Map<String, Object?> _challengeBody({
  String? errcode,
  required String session,
  required List<List<String>> flows,
  List<String>? completed,
  Map<String, Object?> params = const {},
  String? msg,
}) => {
  'errcode': ?errcode,
  'session': session,
  'flows': [
    for (final stages in flows) {'stages': stages},
  ],
  'completed': ?completed,
  'params': params,
  'msg': ?msg,
};

Map<String, Object?> _passwordChallengeBody({
  String? errcode,
  List<String> stages = const ['m.login.password'],
  List<String> completed = const [],
}) => _challengeBody(
  errcode: errcode,
  session: 's1',
  flows: [stages],
  completed: completed,
);

MatrixException uiaPasswordChallenge({
  String? errcode,
  List<String> stages = const ['m.login.password'],
  List<String> completed = const [],
}) => MatrixException.fromJson(
  _passwordChallengeBody(
    errcode: errcode,
    stages: stages,
    completed: completed,
  ),
);

http.Response uiaPasswordChallengeResponse() =>
    http.Response(jsonEncode(_passwordChallengeBody()), 401);

const approvalUrl =
    'https://account.example.org/account/?action=org.matrix.cross_signing_reset';

const approvalStages = ['m.oauth', 'org.matrix.cross_signing_reset'];

Map<String, Object?> _approvalChallengeBody({
  List<String> stages = approvalStages,
  Object? url = approvalUrl,
}) => _challengeBody(
  session: 'dummy',
  flows: [
    for (final stage in stages) [stage],
  ],
  params: {
    for (final stage in stages) stage: {'url': url},
  },
  msg:
      'To reset your end-to-end encryption cross-signing identity, you first '
      'need to approve it at $url and then try again.',
);

MatrixException uiaApprovalChallenge({
  List<String> stages = approvalStages,
  Object? url = approvalUrl,
}) =>
    MatrixException.fromJson(_approvalChallengeBody(stages: stages, url: url));

http.Response uiaApprovalChallengeResponse() =>
    http.Response(jsonEncode(_approvalChallengeBody()), 401);
