import 'package:matrix/matrix.dart' hide CallSession;

import '../../../core/format/human_units.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/event_display.dart';
import '../../../core/matrix/media_size.dart';
import '../../../core/matrix/reply_fallback.dart';

String attachmentInfoText(
  AppLocalizations l10n,
  Event displayEvent,
  MessageKind kind,
) {
  final visual = kind == MessageKind.photo || kind == MessageKind.video;
  final size = visual
      ? mediaSize(displayEvent.mediaWidth, displayEvent.mediaHeight)
      : null;
  final duration = kind == MessageKind.video
      ? displayEvent.mediaDuration
      : null;
  final bytes = displayEvent.fileSize;
  final details = [
    if (size case (final width, final height)) '$width × $height',
    if (duration != null) formatDuration(duration),
    if (bytes != null) formatBytes(l10n, bytes),
  ];
  return details.isEmpty ? l10n.chatNoFileInfo : joinDetails(details);
}

String displayBody(Event event, Timeline timeline) =>
    stripReplyFallback(event.getDisplayEvent(timeline).plaintextBody);

String previewSnippet(AppLocalizations l10n, Event event, Timeline timeline) =>
    summarize(l10n, event.getDisplayEvent(timeline)).text;

const runGap = Duration(minutes: 5);
