import 'package:matrix/matrix.dart' hide CallSession;

import '../../../core/format/human_units.dart';
import '../../../core/matrix/event_display.dart';
import '../../../core/matrix/reply_fallback.dart';

enum AttachmentKind { none, image, video, voice, file, location }

AttachmentKind classifyAttachment(Event displayEvent) =>
    switch (summarize(displayEvent).kind) {
      MessageKind.photo => AttachmentKind.image,
      MessageKind.video => AttachmentKind.video,
      MessageKind.voice => AttachmentKind.voice,
      MessageKind.file => AttachmentKind.file,
      MessageKind.location => AttachmentKind.location,
      MessageKind.text ||
      MessageKind.callSummary ||
      MessageKind.deleted ||
      MessageKind.undecryptable ||
      MessageKind.nonMessage ||
      MessageKind.hiddenSignaling => AttachmentKind.none,
    };

String attachmentInfoText(Event displayEvent, AttachmentKind kind) {
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
  if (size != null) parts.add(formatBytes(size));
  return parts.isEmpty ? 'No file information available' : parts.join(' · ');
}

String displayBody(Event event, Timeline timeline) =>
    stripReplyFallback(event.getDisplayEvent(timeline).plaintextBody);

String previewSnippet(Event event, Timeline timeline) =>
    summarize(event.getDisplayEvent(timeline)).text;

bool isHiddenTimelineEvent(Event e) =>
    !isDisplayableTimelineEvent(e, showHiddenMessages: false);

const runGap = Duration(minutes: 5);

bool isSameLocalDay(DateTime a, DateTime b) {
  final la = a.toLocal();
  final lb = b.toLocal();
  return la.year == lb.year && la.month == lb.month && la.day == lb.day;
}

const _dateDividerMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String dateDividerLabel(DateTime time, DateTime now) {
  if (isSameLocalDay(time, now)) return 'Today';
  if (isSameLocalDay(time, now.subtract(const Duration(days: 1)))) {
    return 'Yesterday';
  }
  final local = time.toLocal();
  final month = _dateDividerMonthNames[local.month - 1];
  return local.year == now.toLocal().year
      ? '$month ${local.day}'
      : '$month ${local.day}, ${local.year}';
}

String formatDuration(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
