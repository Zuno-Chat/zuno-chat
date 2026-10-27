import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../errors/caught_errors.dart';
import '../l10n/l10n.dart';
import 'attachment_actions.dart';

Future<void> saveAttachmentsWithFeedback(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  List<Event> events,
) async {
  try {
    if (events.length == 1) {
      final event = events.single;
      if (await saveAttachment(event)) {
        messenger.showSnackBar(
          SnackBar(content: Text(savedMessage(l10n, event))),
        );
      }
      return;
    }
    final saved = await saveAttachments(events);
    messenger.showSnackBar(
      SnackBar(
        content: Text(savedSummary(l10n, saved: saved, total: events.length)),
      ),
    );
  } catch (e, s) {
    if (!isGalleryAccessDenied(e)) reportCaught('save attachment', e, s);
    messenger.showSnackBar(SnackBar(content: Text(l10n.commonSaveFailed)));
  }
}

Future<void> shareAttachmentsWithFeedback(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  List<Event> events,
) async {
  var preparing = false;
  String? failure;
  try {
    await shareAttachments(
      events,
      onPreparing: () {
        preparing = true;
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.matrixSharePreparing),
            duration: const Duration(minutes: 2),
          ),
        );
      },
    );
  } catch (e, s) {
    reportCaught('share attachment', e, s);
    failure = l10n.matrixShareFailed;
  }
  if (preparing) messenger.hideCurrentSnackBar();
  if (failure != null) {
    messenger.showSnackBar(SnackBar(content: Text(failure)));
  }
}
