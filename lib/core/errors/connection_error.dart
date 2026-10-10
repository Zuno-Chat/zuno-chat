import 'dart:async' show TimeoutException;
import 'dart:io' show SocketException, TlsException;

import 'package:http/http.dart' show ClientException;

import 'native_caught_error.dart';

const _urlErrorDomain = 'NSURLErrorDomain';

const _urlConnectionCodes = {
  -1001,
  -1003,
  -1004,
  -1005,
  -1006,
  -1009,
  -1018,
  -1019,
  -1020,
  -1200,
  -1201,
  -1202,
  -1203,
  -1204,
  -1205,
  -1206,
};

bool isConnectionError(Object error) =>
    error is SocketException ||
    error is TlsException ||
    error is TimeoutException ||
    error is ClientException ||
    (error is NativeCaughtError && _isNativeConnectionError(error));

bool _isNativeConnectionError(NativeCaughtError error) =>
    error.type.startsWith('java.net.') ||
    error.type.startsWith('javax.net.ssl.') ||
    (error.domain == _urlErrorDomain &&
        _urlConnectionCodes.contains(error.code));

String failureMessage(Object error, {required String failed}) =>
    isConnectionError(error)
    ? '$failed Check your connection and try again.'
    : failed;
