import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../errors/caught_errors.dart';
import '../l10n/l10n.dart';
import 'attachment_actions.dart';

class AttachmentActionButtons extends StatelessWidget {
  final Event event;
  final Color? color;

  const AttachmentActionButtons({required this.event, this.color, super.key});

  Future<void> _save(BuildContext context) => saveAttachmentsWithFeedback(
    ScaffoldMessenger.of(context),
    context.l10n,
    [event],
  );

  Future<void> _share(BuildContext context) => shareAttachmentsWithFeedback(
    ScaffoldMessenger.of(context),
    context.l10n,
    [event],
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.share_outlined),
          color: color,
          tooltip: context.l10n.commonShare,
          onPressed: () => _share(context),
        ),
        IconButton(
          icon: const Icon(Icons.download_outlined),
          color: color,
          tooltip: context.l10n.commonSave,
          onPressed: () => _save(context),
        ),
      ],
    );
  }
}

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
