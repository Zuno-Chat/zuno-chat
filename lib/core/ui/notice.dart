import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../errors/caught_errors.dart';
import '../errors/connection_error.dart';
import '../l10n/display_text.dart';
import '../l10n/l10n.dart';

extension Notice on ScaffoldMessengerState {
  void say(@displayText String message) =>
      showSnackBar(SnackBar(content: Text(message)));

  void sayFailed(
    AppLocalizations l10n,
    Object? error, {
    @displayText required String failed,
  }) => say(failureMessage(l10n, error, failed: failed));

  Future<void> copy(String text, {@displayText required String copied}) async {
    await Clipboard.setData(ClipboardData(text: text));
    say(copied);
  }
}

Future<bool> attempt(
  BuildContext context,
  Future<void> Function() action, {
  required String label,
  @displayText required String failed,
  @displayText String? succeeded,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    await action();
  } catch (e, s) {
    reportCaught(label, e, s);
    messenger.sayFailed(l10n, e, failed: failed);
    return false;
  }
  if (succeeded != null) messenger.say(succeeded);
  return true;
}
