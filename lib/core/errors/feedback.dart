import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'crash_reporting.dart';
import 'crash_scrubber.dart';

class FeedbackNotSent implements Exception {
  const FeedbackNotSent();
}

Future<void> sendFeedback(
  String message, {
  String dsn = sentryDsn,
  Transport? transport,
  http.Client? httpClient,
}) async {
  if (dsn.isEmpty) throw const FeedbackNotSent();

  final info = await PackageInfo.fromPlatform();
  final connection = _FailureRecordingClient(httpClient ?? http.Client());
  final options = SentryOptions(dsn: dsn)
    ..environment = 'production'
    ..release = '${info.packageName}@${info.version}+${info.buildNumber}'
    ..sendDefaultPii = false
    ..httpClient = connection;
  if (transport != null) options.transport = transport;

  final scope = Scope(options);
  await scope.setTag('os', Platform.operatingSystemVersion);

  final client = SentryClient(options);
  try {
    final id = await client.captureFeedback(
      SentryFeedback(message: scrubText(message)!),
      scope: scope,
    );
    if (id != SentryId.empty()) return;
    if (connection.failure case (:final error, :final stack)) {
      Error.throwWithStackTrace(error, stack);
    }
    throw const FeedbackNotSent();
  } finally {
    await client.close();
  }
}

class _FailureRecordingClient extends http.BaseClient {
  _FailureRecordingClient(this._inner);

  final http.Client _inner;
  ({Object error, StackTrace stack})? failure;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      return await _inner.send(request);
    } catch (error, stack) {
      failure = (error: error, stack: stack);
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
