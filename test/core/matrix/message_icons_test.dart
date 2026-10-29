import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/matrix/event_display.dart';
import 'package:zuno/core/matrix/message_icons.dart';

void main() {
  CallSummary call(String kind, CallSummaryStatus status) =>
      CallSummary(callId: 'c1', kind: kind, status: status, durationMs: 0);

  test('each attachment and location kind has its icon', () {
    for (final (kind, icon) in [
      (MessageKind.photo, Icons.photo_outlined),
      (MessageKind.video, Icons.videocam_outlined),
      (MessageKind.voice, Icons.mic_none_outlined),
      (MessageKind.file, Icons.insert_drive_file_outlined),
      (MessageKind.location, Icons.location_on_outlined),
      (MessageKind.liveLocation, Icons.share_location_outlined),
    ]) {
      expect(
        messageIcon(MessageSummary(kind: kind, text: '')),
        icon,
        reason: kind.name,
      );
    }
  });

  test('text and messages with nothing to show carry no icon', () {
    for (final kind in [
      MessageKind.text,
      MessageKind.deleted,
      MessageKind.undecryptable,
      MessageKind.nonMessage,
      MessageKind.hiddenSignaling,
    ]) {
      expect(
        messageIcon(MessageSummary(kind: kind, text: '')),
        isNull,
        reason: kind.name,
      );
    }
  });

  test('a call tells voice from video, and missed from declined', () {
    for (final (kind, status, icon) in [
      ('voice', CallSummaryStatus.missed, Icons.call_missed_outlined),
      ('video', CallSummaryStatus.missed, Icons.missed_video_call_outlined),
      ('voice', CallSummaryStatus.declined, Icons.call_end_outlined),
      ('video', CallSummaryStatus.declined, Icons.call_end_outlined),
      ('voice', CallSummaryStatus.ended, Icons.call_outlined),
      ('video', CallSummaryStatus.ended, Icons.videocam_outlined),
    ]) {
      final summary = call(kind, status);
      expect(callSummaryIcon(summary), icon, reason: '$kind $status');
      expect(
        messageIcon(
          MessageSummary(
            kind: MessageKind.callSummary,
            text: '',
            call: summary,
          ),
        ),
        icon,
      );
    }
  });
}
