import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import '../errors/connection_error.dart';

class ServerAnswerFailed implements Exception {
  const ServerAnswerFailed(this.statusCode, {this.oauthError, this.retryAfter});

  final int statusCode;
  final String? oauthError;
  final Duration? retryAfter;

  @override
  String toString() => oauthError == null
      ? 'ServerAnswerFailed($statusCode)'
      : 'ServerAnswerFailed($statusCode, $oauthError)';
}

mixin TypedServerAnswers on MatrixApi {
  @override
  Never unexpectedResponse(http.BaseResponse response, Uint8List body) {
    try {
      super.unexpectedResponse(response, body);
    } on MatrixException {
      rethrow;
    } on Exception {
      throw ServerAnswerFailed(
        response.statusCode,
        oauthError: _oauthErrorIn(body),
        retryAfter: retryAfterIn(response.headers),
      );
    }
  }
}

bool isRateLimit(Object error) => switch (error) {
  MatrixException(error: MatrixError.M_LIMIT_EXCEEDED) ||
  ServerAnswerFailed(statusCode: 429) => true,
  _ => false,
};

bool isServerError(Object error) =>
    error is ServerAnswerFailed && error.statusCode >= 500;

bool isServerOrNetworkFailure(Object error) =>
    isConnectionError(error) ||
    error is MatrixException ||
    error is ServerAnswerFailed;

bool isExpectedServerFailure(Object error) =>
    isConnectionError(error) || isRateLimit(error) || isServerError(error);

Duration? retryAfterIn(Map<String, String> headers) {
  final seconds = int.tryParse(headers['retry-after'] ?? '');
  return seconds == null ? null : Duration(seconds: seconds);
}

String? _oauthErrorIn(Uint8List body) {
  try {
    return switch (jsonDecode(utf8.decode(body))) {
      {'error': final String error} => error,
      _ => null,
    };
  } on FormatException {
    return null;
  }
}
