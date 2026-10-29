import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/encryption.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/display_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/ui/notice.dart';
import 'verification_page.dart';

Future<KeyVerification?> startAndOpenVerification(
  BuildContext context,
  Future<KeyVerification> Function() start, {
  required String label,
  @displayText required String failed,
  bool isOwnDevice = false,
  bool picturesFirst = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final KeyVerification verification;
  try {
    verification = await start();
  } catch (e, s) {
    reportCaught(label, e, s);
    messenger.sayFailed(l10n, e, failed: failed);
    return null;
  }
  if (!context.mounted) {
    unawaited(
      runBestEffort(
        () => verification.cancel('m.user'),
        label: 'cancel unattended verification',
      ),
    );
    return null;
  }
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => VerificationPage(
        keyVerification: verification,
        isOwnDevice: isOwnDevice,
        picturesFirst: picturesFirst,
      ),
    ),
  );
  return verification;
}
