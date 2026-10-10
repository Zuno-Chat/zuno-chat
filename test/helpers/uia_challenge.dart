import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

Map<String, Object?> _passwordChallengeBody({
  String? errcode,
  List<String> stages = const ['m.login.password'],
  List<String> completed = const [],
}) => {
  'errcode': ?errcode,
  'session': 's1',
  'flows': [
    {'stages': stages},
  ],
  'completed': completed,
  'params': <String, Object?>{},
};

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
