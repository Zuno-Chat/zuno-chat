import 'package:flutter/material.dart';

import '../calls/matrixrtc/call_summary_message.dart';
import 'event_display.dart';

IconData? messageIcon(MessageSummary summary) => switch (summary.kind) {
  MessageKind.photo => Icons.photo_outlined,
  MessageKind.video => Icons.videocam_outlined,
  MessageKind.voice => Icons.mic_none_outlined,
  MessageKind.file => Icons.insert_drive_file_outlined,
  MessageKind.location => Icons.location_on_outlined,
  MessageKind.liveLocation => Icons.share_location_outlined,
  MessageKind.callSummary => callSummaryIcon(summary.call!),
  MessageKind.text ||
  MessageKind.deleted ||
  MessageKind.undecryptable ||
  MessageKind.nonMessage ||
  MessageKind.hiddenSignaling => null,
};

IconData callSummaryIcon(CallSummary call) =>
    switch ((call.status, call.isVideo)) {
      (CallSummaryStatus.missed, true) => Icons.missed_video_call_outlined,
      (CallSummaryStatus.missed, false) => Icons.call_missed_outlined,
      (CallSummaryStatus.declined, _) => Icons.call_end_outlined,
      (CallSummaryStatus.ended, true) => Icons.videocam_outlined,
      (CallSummaryStatus.ended, false) => Icons.call_outlined,
    };
