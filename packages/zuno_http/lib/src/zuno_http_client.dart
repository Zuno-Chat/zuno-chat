import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'channel_native_http.dart';
import 'cleartext.dart';
import 'deadlines.dart';
import 'failures.dart';
import 'headers.dart';
import 'native_http.dart';
import 'redirects.dart';
import 'request_body.dart';
import 'response_body.dart';

const _octetStream = 'application/octet-stream';

var _nextId = 1;

class ZunoHttpClient extends http.BaseClient {
  ZunoHttpClient({
    required this._userAgent,
    required this._deadlines,
    NativeHttp? native,
  }) : _native = native ?? ChannelNativeHttp.instance;

  final String _userAgent;
  final HttpDeadlines _deadlines;
  final NativeHttp _native;
  final _calls = <_Call>{};
  var _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) {
      throw http.ClientException(
        'HTTP request failed. Client is already closed.',
        request.url,
      );
    }
    _refuseCleartext(request.url);
    final aborts = _Aborts();
    if (request case http.Abortable(:final abortTrigger?)) {
      abortTrigger
          .whenComplete(
            () => aborts.abort(http.RequestAbortedException(request.url)),
          )
          .ignore();
    }
    final body = request.finalize();
    var method = request.method;
    var url = request.url;
    var headers = headerMap(request.headers);
    final locations = <Uri>[];
    while (true) {
      aborts.check();
      if (_closed) throw http.RequestAbortedException(request.url);
      final call = _Call(
        native: _native,
        original: request,
        method: method,
        url: url,
        headers: headers,
        body: locations.isEmpty ? body : null,
        userAgent: _userAgent,
        deadlines: _deadlines,
        onDone: _calls.remove,
      );
      _calls.add(call);
      aborts.current = call;
      final head = await call.open();
      final redirect = followsRedirect(method, head.status);
      if (!request.followRedirects || !redirect) {
        return call.response(
          head,
          url: locations.isEmpty ? request.url : locations.last,
          isRedirect: redirect,
        );
      }
      call.cancel();
      final last = locations.lastOrNull;
      if (locations.length >= request.maxRedirects) {
        throw http.ClientException('Redirect limit exceeded', last);
      }
      final locationValues = [
        for (final MapEntry(:key, :value) in head.headers.entries)
          if (key.toLowerCase() == 'location') ...value,
      ];
      if (locationValues.length > 1) {
        throw http.ClientException(
          'More than one value for header location',
          last,
        );
      }
      final location = locationValues.firstOrNull;
      if (location == null) {
        throw http.ClientException(
          'Server response has no Location header for redirect',
          last,
        );
      }
      final raw = Uri.parse(location);
      if (locations.contains(raw)) {
        throw http.ClientException('Redirect loop detected', last);
      }
      final next = url.resolveUri(raw);
      _refuseCleartext(next);
      if (head.status == 303 && method == 'POST') method = 'GET';
      headers = headerMap(redirectHeaders(url, next, headers));
      locations.add(raw);
      url = next;
    }
  }

  @override
  void close() {
    _closed = true;
    for (final call in _calls.toList()) {
      call.abort(http.RequestAbortedException(call.url));
    }
  }
}

class _Aborts {
  _Call? current;
  Object? _error;

  void abort(Object error) {
    _error ??= error;
    current?.abort(error);
  }

  void check() {
    final error = _error;
    if (error != null) throw error;
  }
}

class _Call {
  _Call({
    required this._native,
    required this._original,
    required this._method,
    required this.url,
    required this._headers,
    required this._body,
    required this._userAgent,
    required this._deadlines,
    required this._onDone,
  }) : id = _nextId++;

  final NativeHttp _native;
  final http.BaseRequest _original;
  final String _method;
  final Uri url;
  final Map<String, String> _headers;
  final Stream<List<int>>? _body;
  final String _userAgent;
  final HttpDeadlines _deadlines;
  final void Function(_Call call) _onDone;
  final int id;
  ResponseBody? _response;
  RequestBodyPump? _upload;
  Object? _stopError;
  Timer? _connectCheck;
  Timer? _thinking;
  var _answered = false;
  var _ended = false;

  Duration? get _thinkTime => switch (_original) {
    DeadlineRequest(:final thinkTime?) => thinkTime,
    _ => _deadlines.thinkTime,
  };

  Future<NativeHead> open() async {
    final body = _body;
    final length = body == null ? 0 : _original.contentLength;
    final hasBody = length == null || length > 0;
    final opening = _native.open(
      NativeRequest(
        id: id,
        method: _method,
        url: url,
        headers: _nativeHeaders(hasBody: hasBody),
        bodyLength: hasBody ? length : null,
        hasBody: hasBody,
      ),
    );
    _connectCheck = Timer(connectDeadline, _checkConnected);
    _startThinking();
    if (hasBody && body != null) {
      final upload = _upload = RequestBodyPump(
        native: _native,
        id: id,
        body: body,
        replay: replayOf(_original),
        length: length,
        uri: url,
        onProgress: _startThinking,
        onFailure: abort,
      );
      unawaited(upload.run());
    } else if (body != null) {
      unawaited(body.listen(null).cancel());
    }
    final NativeHead head;
    try {
      head = await opening;
    } on Object catch (error) {
      cancel();
      throw _failureFor(error);
    }
    _answered = true;
    _stopTimers();
    final stopped = _stopError;
    if (stopped != null) {
      cancel();
      throw stopped;
    }
    return head;
  }

  void _startThinking() {
    _thinking?.cancel();
    final thinkTime = _thinkTime;
    if (thinkTime == null || _answered || _ended) return;
    _thinking = Timer(
      thinkTime,
      () => abort(
        NativeHttpException(
          HttpFailureKind.timedOut,
          'No answer within ${thinkTime.inSeconds} s',
          url,
        ),
      ),
    );
  }

  void _checkConnected() {
    if (_answered || _ended) return;
    _native.status(id).then((phase) {
      if (phase != NativePhase.connecting || _answered) return;
      abort(
        NativeHttpException(
          HttpFailureKind.connectTimedOut,
          'No connection within ${connectDeadline.inSeconds} s',
          url,
        ),
      );
    }, onError: (Object _) {}).ignore();
  }

  void _stopTimers() {
    _connectCheck?.cancel();
    _thinking?.cancel();
  }

  void abort(Object error) {
    if (_ended) return;
    _stopError ??= error;
    _response?.fail(error);
    cancel();
  }

  void cancel() {
    if (_ended) return;
    _markEnded();
    _native.cancel(id).ignore();
  }

  void _markEnded() {
    if (_ended) return;
    _ended = true;
    _stopTimers();
    _upload?.stop();
    _onDone(this);
  }

  Object _failureFor(Object error) {
    final stopped = _stopError;
    if (stopped != null) return stopped;
    if (error is NativeHttpException &&
        error.kind == HttpFailureKind.cancelled) {
      return http.RequestAbortedException(url);
    }
    return error;
  }

  Map<String, String> _nativeHeaders({required bool hasBody}) {
    final headers = withUserAgent(_headers, _userAgent)..remove('host');
    if (hasBody) headers.putIfAbsent('content-type', () => _octetStream);
    return headers;
  }

  http.StreamedResponse response(
    NativeHead head, {
    required Uri url,
    required bool isRedirect,
  }) {
    final headers = _joined(head.headers);
    final stopped = _stopError;
    final Stream<List<int>> stream;
    if (stopped != null) {
      cancel();
      stream = Stream.error(stopped);
    } else if (_hasNoBody(head.status)) {
      _drain();
      stream = const Stream.empty();
    } else {
      final body = _response = ResponseBody(
        native: _native,
        id: id,
        uri: this.url,
        onEnd: _finished,
        onFailure: (error) {
          _markEnded();
          return _failureFor(error);
        },
        onCancel: cancel,
        idle: _deadlines.idle,
      );
      stream = body.stream;
    }
    final declaredLength = int.tryParse(headers['content-length'] ?? '');
    return _NativeStreamedResponse(
      stream,
      head.status,
      url: url,
      contentLength:
          headers.containsKey('content-encoding') ||
              declaredLength == null ||
              declaredLength < 0
          ? null
          : declaredLength,
      request: _original,
      headers: headers,
      isRedirect: isRedirect,
      persistentConnection: !(headers['connection'] ?? '')
          .toLowerCase()
          .contains('close'),
      reasonPhrase: head.reason,
    );
  }

  bool _hasNoBody(int status) =>
      _method == 'HEAD' ||
      status == 204 ||
      status == 304 ||
      (status >= 100 && status < 200);

  void _drain() {
    _native.read(id).then((chunk) {
      if (chunk.end) {
        _finished(chunk.protocol);
      } else {
        _drain();
      }
    }, onError: (Object _) => _markEnded()).ignore();
  }

  void _finished(String? protocol) {
    _markEnded();
    if (!kReleaseMode) {
      debugPrint('zuno/http: $_method ${url.host} ${protocol ?? 'unknown'}');
    }
  }
}

void _refuseCleartext(Uri url) {
  if (cleartextRefusal(url, secureScheme: 'https') case final refusal?) {
    throw refusal;
  }
}

Map<String, String> _joined(Map<String, List<String>> native) {
  final joined = <String, String>{};
  native.forEach((name, values) {
    final key = name.toLowerCase();
    final value = values.map((value) => value.trimRight()).join(',');
    final earlier = joined[key];
    joined[key] = earlier == null ? value : '$earlier,$value';
  });
  return joined;
}

class _NativeStreamedResponse extends http.StreamedResponse
    implements http.BaseResponseWithUrl {
  _NativeStreamedResponse(
    super.stream,
    super.statusCode, {
    required this.url,
    super.contentLength,
    super.request,
    super.headers,
    super.isRedirect,
    super.persistentConnection,
    super.reasonPhrase,
  });

  @override
  final Uri url;
}
