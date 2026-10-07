import 'dart:async' show TimeoutException;
import 'dart:io' show SocketException, TlsException;

import 'package:http/http.dart' show ClientException;

bool isConnectionError(Object error) =>
    error is SocketException ||
    error is TlsException ||
    error is TimeoutException ||
    error is ClientException;

String failureMessage(Object error, {required String failed}) =>
    isConnectionError(error)
    ? '$failed Check your connection and try again.'
    : failed;
