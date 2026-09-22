import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../errors/best_effort.dart';
import 'attachment_actions.dart';

class AttachmentActionButtons extends StatelessWidget {
  final Event event;
  final Color? color;

  const AttachmentActionButtons({required this.event, this.color, super.key});

  Future<void> _save(BuildContext context) =>
      saveAttachmentWithFeedback(ScaffoldMessenger.of(context), event);

  Future<void> _share(BuildContext context) =>
      shareAttachmentsWithFeedback(ScaffoldMessenger.of(context), [event]);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.share_outlined),
          color: color,
          tooltip: 'Share',
          onPressed: () => _share(context),
        ),
        IconButton(
          icon: const Icon(Icons.download_outlined),
          color: color,
          tooltip: 'Save',
          onPressed: () => _save(context),
        ),
      ],
    );
  }
}

Future<void> saveAttachmentWithFeedback(
  ScaffoldMessengerState messenger,
  Event event,
) async {
  try {
    final message = await saveAttachment(event);
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  } catch (e) {
    logCaught('save attachment', e);
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not save. Try again.')),
    );
  }
}

Future<void> shareAttachmentsWithFeedback(
  ScaffoldMessengerState messenger,
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
          const SnackBar(
            content: Text('Preparing to share…'),
            duration: Duration(minutes: 2),
          ),
        );
      },
    );
  } catch (e) {
    logCaught('share attachment', e);
    failure = 'Could not share. Try again.';
  }
  if (preparing) messenger.hideCurrentSnackBar();
  if (failure != null) {
    messenger.showSnackBar(SnackBar(content: Text(failure)));
  }
}
