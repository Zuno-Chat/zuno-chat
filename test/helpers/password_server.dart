import 'dart:convert';

import 'package:http/http.dart' as http;

http.Response? passwordServerAnswer(http.Request request) {
  final path = request.url.path;
  if (path.endsWith('/login')) {
    return http.Response(
      jsonEncode({
        'flows': [
          {'type': 'm.login.password'},
        ],
      }),
      200,
    );
  }
  if (path.endsWith('/auth_metadata')) {
    return http.Response(
      jsonEncode({'errcode': 'M_UNRECOGNIZED', 'error': 'Unrecognized'}),
      404,
    );
  }
  return null;
}
