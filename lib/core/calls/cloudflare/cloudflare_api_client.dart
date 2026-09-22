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
  final String? errorDescription;

  const CfTrack({
    required this.location,
    this.mid,
    this.trackName,
    this.sessionId,
    this.errorCode,
    this.errorDescription,
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
    errorDescription: json['errorDescription'] as String?,
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
  final String? errorDescription;

  const CfTracksResult({
    required this.requiresImmediateRenegotiation,
    required this.sessionDescription,
    required this.tracks,
    this.errorCode,
    this.errorDescription,
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
    errorDescription: json['errorDescription'] as String?,
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

CfTracksResult _tracksResultOrThrow(Map<String, dynamic> json) {
  final result = CfTracksResult.fromJson(json);
  if (result.hasError) {
    throw CloudflareCallsException(
      '${result.errorCode}: ${result.errorDescription}',
    );
  }
  return result;
}

class CloudflareApiClient {
  final Uri baseUri;
  final Future<String> Function() authorization;
  final http.Client httpClient;
  final bool _ownsHttpClient;

  CloudflareApiClient({
    required this.baseUri,
    required this.authorization,
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  Uri _uri(String path) => baseUri.replace(
    pathSegments: [
      ...baseUri.pathSegments.where((segment) => segment.isNotEmpty),
      ...path.split('/').where((segment) => segment.isNotEmpty),
    ],
  );

  static const _maxAttempts = 3;
  static const _baseDelay = Duration(milliseconds: 150);
  static const _maxDelay = Duration(milliseconds: 1500);
  static const _requestDeadline = Duration(seconds: 15);

  Future<Map<String, dynamic>> _send(
    String method,
    Uri uri,
    Map<String, Object?>? body,
  ) => retryWithBackoff(
    () => _sendOnce(method, uri, body),
    label: '$method ${uri.path}',
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
    String method,
    Uri uri,
    Map<String, Object?>? body,
  ) async {
    final response = await _request(method, uri, body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudflareCallsException(
        'HTTP ${response.statusCode} from ${uri.path}: ${response.body}',
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
    final json = await _send('POST', _uri('/sessions/new'), null);
    final sessionId = json['sessionId'] as String?;
    if (sessionId == null) {
      throw CloudflareCallsException(
        'sessions/new did not return a sessionId: ${json['errorDescription'] ?? json}',
      );
    }
    return sessionId;
  }

  Future<CfTracksResult> pushLocalTracks({
    required String sessionId,
    required CfSessionDescription offer,
    required List<CfTrack> tracks,
  }) async {
    final json = await _send('POST', _uri('/sessions/$sessionId/tracks/new'), {
      'sessionDescription': offer.toJson(),
      'tracks': tracks.map((t) => t.toJson()).toList(),
    });
    return _tracksResultOrThrow(json);
  }

  Future<CfTracksResult> pullRemoteTracks({
    required String sessionId,
    required List<CfTrack> tracks,
  }) async {
    final json = await _send('POST', _uri('/sessions/$sessionId/tracks/new'), {
      'tracks': tracks.map((t) => t.toJson()).toList(),
    });
    return _tracksResultOrThrow(json);
  }

  Future<CfSessionDescription?> renegotiate({
    required String sessionId,
    required CfSessionDescription offer,
  }) async {
    final json = await _send('PUT', _uri('/sessions/$sessionId/renegotiate'), {
      'sessionDescription': offer.toJson(),
    });
    if (json['errorCode'] != null) {
      throw CloudflareCallsException(
        '${json['errorCode']}: ${json['errorDescription']}',
      );
    }
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
    final json = await _send('PUT', _uri('/sessions/$sessionId/tracks/close'), {
      'tracks': mids.map((m) => {'mid': m}).toList(),
      'force': force,
      'sessionDescription': sessionDescription.toJson(),
    });
    return CfTracksResult.fromJson(json);
  }

  void close() {
    if (_ownsHttpClient) httpClient.close();
  }
}
