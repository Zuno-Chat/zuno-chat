import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/format/date_labels.dart';
import '../../../core/l10n/display_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/location/live_location_sharing.dart';
import '../../../core/matrix/abuse_report.dart';
import '../../../core/matrix/attachment_feedback.dart';
import '../../../core/matrix/event_display.dart';
import '../../../core/matrix/room_encryption.dart';
import '../../../core/matrix/room_permission.dart';
import '../../../core/security/security_emphasis.dart';
import '../../../core/ui/sheet.dart';
import '../../reports/presentation/report_sheet.dart';
import '../data/discarded_sends.dart';
import '../data/forwarding.dart';
import '../data/message_kinds.dart';
import '../data/room_sender.dart';
import '../data/unsent_events.dart';
import 'forward_media.dart';
import 'message_actions_sheet.dart';
import 'message_contents/reactions_row.dart';
import 'seen_by_tile.dart';
import 'sender_device_tile.dart';

Future<void> showMessageActions(
  BuildContext context,
  WidgetRef ref, {
  required Room room,
  required Timeline timeline,
  required Event event,
  List<Event>? gallery,
  required void Function(Event event) onReply,
  required void Function(Event event) onEdit,
}) async {
  if (event.redacted) return;
  final isOwn = event.senderId == room.client.userID;
  final sent = event.status.isSent;
  final displayEvent = event.getDisplayEvent(timeline);
  final canPost = canPostInRoom(room);
  final canEdit =
      canPost &&
      sent &&
      isOwn &&
      !event.hasAttachment &&
      displayEvent.messageType == MessageTypes.Text;
  final attachmentKind = classifyAttachment(displayEvent);
  final isAttachment = switch (attachmentKind) {
    AttachmentKind.none ||
    AttachmentKind.location ||
    AttachmentKind.liveLocation => false,
    AttachmentKind.image ||
    AttachmentKind.video ||
    AttachmentKind.voice ||
    AttachmentKind.file => true,
  };
  final isTextMessage =
      !isAttachment && attachmentKind != AttachmentKind.liveLocation;
  final canDelete =
      (isOwn || room.canRedact) &&
      (sent ||
          isNotSent(event) ||
          gallery != null ||
          (isOwn && isAttachment && event.status.isSending));
  final messages = gallery ?? [event];
  final shown = withEditApplied(event, displayEvent);
  final media = gallery == null
      ? [shown]
      : [for (final item in gallery) withLatestEdit(item, timeline)];
  final forwardable = media.where(canForward).toList();
  final l10n = context.l10n;
  final labels = DateLabels.of(context);

  final action = await showMessageActionsSheet(
    context,
    canRespond: canRespondTo(room, event),
    canEdit: canEdit,
    canDelete: canDelete,
    isOwn: isOwn,
    isTextMessage: isTextMessage,
    isAttachment: isAttachment,
    galleryCount: gallery?.length ?? 0,
    forwardCount: forwardable.length,
    facts: [
      if (isAttachment)
        MessageFact(
          icon: Icons.info_outline,
          child: Text(attachmentInfoText(l10n, shown, attachmentKind)),
        ),
      MessageFact(
        icon: Icons.schedule_outlined,
        child: Text(switch (displayEvent.status) {
          EventStatus.error => l10n.chatNotSent,
          EventStatus.sending => l10n.chatSending,
          _ => l10n.chatSentAt(labels.dateTime(event.originServerTs)),
        }),
      ),
      if (sentInClear(messages, timeline))
        MessageFact(
          icon: notEncryptedIcon,
          iconColor: notEncryptedColor(context),
          child: Text(l10n.chatMessageNotEncryptedHint),
        ),
      if (!isOwn) SenderDeviceTile(event: event),
      if (isOwn) SeenByTile(room: room, event: event),
    ],
    onReact: (key) => reactToMessage(context, event, timeline, key),
    onMoreReactions: () => pickReaction(context, event, timeline),
  );
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  switch (action) {
    case MessageAction.reply:
      onReply(event);
    case MessageAction.edit:
      onEdit(event);
    case MessageAction.delete:
      await _deleteMessages(
        context,
        ref,
        room,
        timeline,
        messages,
        gallery: gallery != null,
      );
    case MessageAction.forward:
      await forwardMedia(context, ref, forwardable);
    case MessageAction.share:
      await shareAttachmentsWithFeedback(messenger, l10n, media);
    case MessageAction.save:
      await saveAttachmentsWithFeedback(messenger, l10n, media);
    case MessageAction.copy:
      await Clipboard.setData(
        ClipboardData(text: displayBody(event, timeline)),
      );
      _say(messenger, l10n.chatCopied);
    case MessageAction.report:
      await _reportMessage(context, room, event);
    case null:
      break;
  }
}

Future<void> reactToMessage(
  BuildContext context,
  Event event,
  Timeline timeline,
  String key,
) => toggleReactionWithFeedback(
  ScaffoldMessenger.of(context),
  context.l10n,
  event,
  timeline,
  key,
);

Future<void> pickReaction(
  BuildContext context,
  Event event,
  Timeline timeline,
) async {
  final key = await showSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SizedBox(
      height: 320,
      child: EmojiPicker(
        onEmojiSelected: (category, emoji) =>
            Navigator.of(context).pop(emoji.emoji),
      ),
    ),
  );
  if (key == null || !context.mounted) return;
  await reactToMessage(context, event, timeline, key);
}

Future<void> _reportMessage(
  BuildContext context,
  Room room,
  Event event,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final sent = await showReportSheet(
    context,
    title: l10n.chatReportTitle,
    explanation: room.isDirectChat
        ? l10n.chatReportExplainDirect
        : l10n.chatReportExplainGroup,
    onSend: (reason, note) => reportMessage(event, reason, note: note),
  );
  if (sent) _say(messenger, l10n.commonReportSent);
}

Future<void> _deleteMessages(
  BuildContext context,
  WidgetRef ref,
  Room room,
  Timeline timeline,
  List<Event> events, {
  required bool gallery,
}) async {
  final many = events.length > 1;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.chatDeleteTitle(events.length)),
      content: Text(switch (many) {
        true => context.l10n.chatDeleteManyBody,
        false when isNotSent(events.single) =>
          context.l10n.chatDeleteUnsentBody,
        false => context.l10n.chatDeleteOneBody,
      }),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            many ? context.l10n.chatDeleteAll : context.l10n.commonDelete,
          ),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final sharing = ref.read(liveLocationSharingProvider);
  final sender = ref.read(roomSenderProvider(room));
  if (gallery) await sender.dropGalleries(events);
  var failed = false;
  for (final event in events.map((event) => _current(event, timeline))) {
    try {
      await sharing.stopShareStartedBy(event);
      if (event.status.isSent) {
        await room.redactEvent(event.eventId);
      } else {
        await sender.discardUnsent(event);
      }
    } catch (e, s) {
      reportCaught('delete message', e, s);
      failed = true;
    }
  }
  if (!failed) return;
  _say(messenger, many ? l10n.chatDeleteManyFailed : l10n.chatDeleteOneFailed);
}

Event _current(Event event, Timeline timeline) {
  final id = sendIdentity(event).txid;
  return timeline.events
          .where((e) => e.matchesEventOrTransactionId(id))
          .firstOrNull ??
      event;
}

void _say(ScaffoldMessengerState messenger, @displayText String message) =>
    messenger.showSnackBar(SnackBar(content: Text(message)));
