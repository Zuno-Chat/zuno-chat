import 'package:matrix/matrix.dart' hide CallSession;

import '../../../core/format/human_units.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/event_display.dart';
import '../../../core/matrix/reply_fallback.dart';

enum AttachmentKind { none, image, video, voice, file, location, liveLocation }

AttachmentKind classifyAttachment(Event displayEvent) =>
    switch (messageKindOf(displayEvent)) {
      MessageKind.photo => AttachmentKind.image,
      MessageKind.video => AttachmentKind.video,
      MessageKind.voice => AttachmentKind.voice,
      MessageKind.file => AttachmentKind.file,
      MessageKind.location => AttachmentKind.location,
      MessageKind.liveLocation => AttachmentKind.liveLocation,
      MessageKind.text ||
      MessageKind.callSummary ||
      MessageKind.deleted ||
      MessageKind.undecryptable ||
      MessageKind.nonMessage ||
      MessageKind.hiddenSignaling => AttachmentKind.none,
    };

String attachmentInfoText(
  AppLocalizations l10n,
  Event displayEvent,
  AttachmentKind kind,
) {
  final info = displayEvent.infoMap;
  final size = info.tryGet<int>('size');
  final parts = <String>[];
  if (kind == AttachmentKind.image || kind == AttachmentKind.video) {
    final width = info.tryGet<int>('w');
    final height = info.tryGet<int>('h');
    if (width != null && height != null) parts.add('$width × $height');
  }
  if (kind == AttachmentKind.video) {
    final durationMs = info.tryGet<int>('duration');
    if (durationMs != null) {
      parts.add(formatDuration(Duration(milliseconds: durationMs)));
    }
  }
  if (size != null) parts.add(formatBytes(l10n, size));
  return parts.isEmpty ? l10n.chatNoFileInfo : parts.join(' · ');
}

String displayBody(Event event, Timeline timeline) =>
    stripReplyFallback(event.getDisplayEvent(timeline).plaintextBody);

String previewSnippet(AppLocalizations l10n, Event event, Timeline timeline) =>
    summarize(l10n, event.getDisplayEvent(timeline)).text;

const runGap = Duration(minutes: 5);
