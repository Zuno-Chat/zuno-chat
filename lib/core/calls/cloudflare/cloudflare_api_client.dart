import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../../errors/retry_backoff.dart';
import 'calls_module.dart';

class CfSessionDescription {
  final String sdp;
  final String type;

  const CfSessionDescription({required this.sdp, required this.type});

  factory CfSessionDescription.fromJson(Map<String, dynamic> json) =>
      CfSessionDescription(
        sdp: json['sdp'] as String,
        type: json['type'] as String,
      );

  Map<String, Object?> toJson() => {'sdp': sdp, 'type': type};
}

class CfTrack {
  final String? location;
  final String? mid;
  final String? trackName;
  final String? sessionId;
  final String? errorCode;

  const CfTrack({
    required this.location,
    this.mid,
    this.trackName,
    this.sessionId,
    this.errorCode,
  });

  factory CfTrack.local({required String mid, required String trackName}) =>
      CfTrack(location: 'local', mid: mid, trackName: trackName);

  factory CfTrack.remote({
    required String sessionId,
    required String trackName,
  }) => CfTrack(location: 'remote', sessionId: sessionId, trackName: trackName);

  factory CfTrack.fromJson(Map<String, dynamic> json) => CfTrack(
    location: json['location'] as String?,
    mid: json['mid'] as String?,
    trackName: json['trackName'] as String?,
    sessionId: json['sessionId'] as String?,
    errorCode: json['errorCode'] as String?,
  );

  Map<String, Object?> toJson() => {
    if (location != null) 'location': location,
    if (mid != null) 'mid': mid,
    if (trackName != null) 'trackName': trackName,
    if (sessionId != null) 'sessionId': sessionId,
  };

  bool get hasError => errorCode != null;
}

class CfTracksResult {
  final bool requiresImmediateRenegotiation;
  final CfSessionDescription? sessionDescription;
  final List<CfTrack> tracks;
  final String? errorCode;

  const CfTracksResult({
    required this.requiresImmediateRenegotiation,
    required this.sessionDescription,
    required this.tracks,
    this.errorCode,
  });

  bool get hasError => errorCode != null;

  factory CfTracksResult.fromJson(Map<String, dynamic> json) => CfTracksResult(
    requiresImmediateRenegotiation:
        json['requiresImmediateRenegotiation'] as bool? ?? false,
    sessionDescription: json['sessionDescription'] == null
        ? null
        : CfSessionDescription.fromJson(
            json['sessionDescription'] as Map<String, dynamic>,
          ),
    tracks: (json['tracks'] as List<dynamic>? ?? [])
        .map((t) => CfTrack.fromJson(t as Map<String, dynamic>))
        .toList(),
    errorCode: json['errorCode'] as String?,
  );
}

class CloudflareCallsException implements Exception {
  final String message;
  final int? statusCode;
  final Duration? retryAfter;

  CloudflareCallsException(this.message, {this.statusCode, this.retryAfter});

  @override
  String toString() => 'CloudflareCallsException: $message';
}

class _Endpoint {
  const _Endpoint(this.method, this.route);

  final String method;
  final String route;

  @override
  String toString() => '$method $route';
}

const _sessionSegment = '{id}';
const _newSession = _Endpoint('POST', '/sessions/new');
const _newTracks = _Endpoint('POST', '/sessions/$_sessionSegment/tracks/new');
const _renegotiate = _Endpoint('PUT', '/sessions/$_sessionSegment/renegotiate');
const _closeTracks = _Endpoint(
  'PUT',
  '/sessions/$_sessionSegment/tracks/close',
);

void _throwIfRefused(Map<String, dynamic> json, _Endpoint endpoint) {
  if (json['errorCode'] == null) return;
  throw CloudflareCallsException(
    '${moduleErrorCode(json) ?? 'an error'} from $endpoint',
  );
}

class CloudflareApiClient {
  final Uri Function() baseUri;
  final Future<String> Function() authorization;
  final http.Client httpClient;
  final bool _ownsHttpClient;

  CloudflareApiClient({
    required this.baseUri,
    required this.authorization,
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  Uri _uri(_Endpoint endpoint, String? sessionId) {
    final base = baseUri();
    return base.replace(
      pathSegments: [
        ...base.pathSegments.where((segment) => segment.isNotEmpty),
        for (final segment in endpoint.route.split('/'))
          if (segment == _sessionSegment)
            sessionId!
          else if (segment.isNotEmpty)
            segment,
      ],
    );
  }

  static const _maxAttempts = 3;
  static const _baseDelay = Duration(milliseconds: 150);
  static const _maxDelay = Duration(milliseconds: 1500);
  static const _requestDeadline = Duration(seconds: 15);

  Future<Map<String, dynamic>> _send(
    _Endpoint endpoint, {
    String? sessionId,
    Map<String, Object?>? body,
  }) => retryWithBackoff(
    () => _sendOnce(endpoint, _uri(endpoint, sessionId), body),
    label: '$endpoint',
    maxAttempts: _maxAttempts,
    baseDelay: _baseDelay,
    maxDelay: _maxDelay,
    retryIf: (error) =>
        error is SocketException ||
        (error is CloudflareCallsException && error.statusCode == 429),
    retryAfter: (error) =>
        error is CloudflareCallsException ? error.retryAfter : null,
  );

  Future<Map<String, dynamic>> _sendOnce(
    _Endpoint endpoint,
    Uri uri,
    Map<String, Object?>? body,
  ) async {
    final response = await _request(endpoint.method, uri, body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudflareCallsException(
        moduleFailure(response, '$endpoint'),
        statusCode: response.statusCode,
        retryAfter: retryAfterOf(response),
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<http.Response> _request(
    String method,
    Uri uri,
    Map<String, Object?>? body,
  ) async {
    final headers = {
      'Authorization': await authorization(),
      'Content-Type': 'application/json',
    };
    final encoded = body == null ? null : jsonEncode(body);
    final pending = switch (method) {
      'POST' => httpClient.post(uri, headers: headers, body: encoded),
      'PUT' => httpClient.put(uri, headers: headers, body: encoded),
      'GET' => httpClient.get(uri, headers: headers),
      _ => throw ArgumentError('Unsupported method $method'),
    };
    return pending.timeout(_requestDeadline);
  }

  Future<String> createSession() async {
    final json = await _send(_newSession);
    final sessionId = json['sessionId'] as String?;
    if (sessionId == null) {
      final code = moduleErrorCode(json);
      throw CloudflareCallsException(
        '$_newSession returned no session${code == null ? '' : ': $code'}',
      );
    }
    return sessionId;
  }

  Future<CfTracksResult> pushLocalTracks({
    required String sessionId,
    required CfSessionDescription offer,
    required List<CfTrack> tracks,
  }) async {
    final json = await _send(
      _newTracks,
      sessionId: sessionId,
      body: {
        'sessionDescription': offer.toJson(),
        'tracks': tracks.map((t) => t.toJson()).toList(),
      },
    );
    _throwIfRefused(json, _newTracks);
    return CfTracksResult.fromJson(json);
  }

  Future<CfTracksResult> pullRemoteTracks({
    required String sessionId,
    required List<CfTrack> tracks,
  }) async {
    final json = await _send(
      _newTracks,
      sessionId: sessionId,
      body: {'tracks': tracks.map((t) => t.toJson()).toList()},
    );
    _throwIfRefused(json, _newTracks);
    return CfTracksResult.fromJson(json);
  }

  Future<CfSessionDescription?> renegotiate({
    required String sessionId,
    required CfSessionDescription offer,
  }) async {
    final json = await _send(
      _renegotiate,
      sessionId: sessionId,
      body: {'sessionDescription': offer.toJson()},
    );
    _throwIfRefused(json, _renegotiate);
    final sessionDescription = json['sessionDescription'];
    if (sessionDescription == null) return null;
    return CfSessionDescription.fromJson(
      sessionDescription as Map<String, dynamic>,
    );
  }

  Future<CfTracksResult> closeTracks({
    required String sessionId,
    required List<String> mids,
    required CfSessionDescription sessionDescription,
    bool force = false,
  }) async {
    final json = await _send(
      _closeTracks,
      sessionId: sessionId,
      body: {
        'tracks': mids.map((m) => {'mid': m}).toList(),
        'force': force,
        'sessionDescription': sessionDescription.toJson(),
      },
    );
    return CfTracksResult.fromJson(json);
  }

  void close() {
    if (_ownsHttpClient) httpClient.close();
  }
}
