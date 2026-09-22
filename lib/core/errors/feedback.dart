import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'crash_reporting.dart';
import 'crash_scrubber.dart';

class FeedbackNotSent implements Exception {
  const FeedbackNotSent();
}

const feedbackAvailable = sentryDsn != '';

Future<void> sendFeedback(
  String message, {
  String dsn = sentryDsn,
  Transport? transport,
}) async {
  if (dsn.isEmpty) throw const FeedbackNotSent();

  final info = await PackageInfo.fromPlatform();
  final options = SentryOptions(dsn: dsn)
    ..environment = 'production'
    ..release = '${info.packageName}@${info.version}+${info.buildNumber}'
    ..sendDefaultPii = false;
  if (transport != null) options.transport = transport;

  final scope = Scope(options);
  await scope.setTag('os', Platform.operatingSystemVersion);

  final client = SentryClient(options);
  try {
    final id = await client.captureFeedback(
      SentryFeedback(message: scrubText(message)!),
      scope: scope,
    );
    if (id == SentryId.empty()) throw const FeedbackNotSent();
  } finally {
    await client.close();
  }
}
