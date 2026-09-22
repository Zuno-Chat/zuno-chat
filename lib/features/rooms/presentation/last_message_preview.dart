import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/matrixrtc/call_summary_message.dart';
import '../../../core/errors/best_effort.dart';
import '../../../core/matrix/event_display.dart';
import '../../../core/matrix/retry_decrypt_last_event.dart';
import '../../../core/matrix/undecryptable_event.dart';
import '../../../core/ui/line_strut.dart';
import '../../chat/presentation/undecryptable_message.dart';

class LastMessagePreview extends StatefulWidget {
  final Room room;
  final Event? event;

  const LastMessagePreview({
    required this.room,
    required this.event,
    super.key,
  });

  @override
  State<LastMessagePreview> createState() => _LastMessagePreviewState();
}

const _sessionKeyRetryDebounce = Duration(milliseconds: 300);

class _LastMessagePreviewState extends State<LastMessagePreview> {
  Event? _resolvedEvent;
  StreamSubscription<String>? _sessionKeySub;
  Timer? _retryDebounceTimer;

  @override
  void initState() {
    super.initState();
    _resolvedEvent = widget.event;
    _listenForSessionKeys();
    _maybeRetryDecrypt();
  }

  @override
  void didUpdateWidget(covariant LastMessagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final eventChanged = !identical(oldWidget.event, widget.event);
    if (eventChanged) _resolvedEvent = widget.event;
    if (eventChanged || oldWidget.room.id != widget.room.id) {
      _listenForSessionKeys();
    }
    _maybeRetryDecrypt();
  }

  @override
  void dispose() {
    _retryDebounceTimer?.cancel();
    _sessionKeySub?.cancel();
    super.dispose();
  }

  void _listenForSessionKeys() {
    _retryDebounceTimer?.cancel();
    _sessionKeySub?.cancel();
    _sessionKeySub = null;
    final event = _resolvedEvent;
    if (event == null || !isUndecryptableEvent(event)) return;
    _sessionKeySub = widget.room.onSessionKeyReceived.stream.listen((_) {
      _retryDebounceTimer?.cancel();
      _retryDebounceTimer = Timer(_sessionKeyRetryDebounce, _maybeRetryDecrypt);
    });
  }

  void _maybeRetryDecrypt() {
    final event = _resolvedEvent;
    if (event == null) return;
    unawaited(
      runBestEffort(() async {
        final decrypted = await retryDecryptIfUndecryptable(widget.room, event);
        if (!mounted || decrypted == null) return;
        setState(() => _resolvedEvent = decrypted);
        _listenForSessionKeys();
      }, label: 'retryDecrypt ${widget.room.id}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = _resolvedEvent;
    final strut = inheritedLineStrut(context);
    if (event == null) return Text('No messages', strutStyle: strut);

    if (!isPreviewableLastEvent(event)) return Text('', strutStyle: strut);

    final summary = summarize(event);

    switch (summary.kind) {
      case MessageKind.deleted:
        return Text(
          summary.text,
          strutStyle: strut,
          style: const TextStyle(fontStyle: FontStyle.italic),
        );
      case MessageKind.undecryptable:
        return const UndecryptablePreviewText();
      case MessageKind.photo:
        return _iconLine(context, Icons.photo_outlined, summary.text);
      case MessageKind.video:
        return _iconLine(context, Icons.videocam_outlined, summary.text);
      case MessageKind.voice:
        return _iconLine(context, Icons.mic_none_outlined, summary.text);
      case MessageKind.file:
        return _iconLine(
          context,
          Icons.insert_drive_file_outlined,
          summary.text,
        );
      case MessageKind.location:
        return _iconLine(context, Icons.location_on_outlined, summary.text);
      case MessageKind.callSummary:
        final missed = summary.call!.status == CallSummaryStatus.missed;
        return _iconLine(
          context,
          _callSummaryIcon(summary.call!),
          summary.text,
          color: missed ? Theme.of(context).colorScheme.error : null,
        );
      case MessageKind.text:
        return Text(
          summary.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          strutStyle: strut,
        );
      case MessageKind.nonMessage:
      case MessageKind.hiddenSignaling:
        return const SizedBox.shrink();
    }
  }

  Widget _iconLine(
    BuildContext context,
    IconData icon,
    String label, {
    Color? color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            strutStyle: inheritedLineStrut(context),
            style: color == null ? null : TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}

IconData _callSummaryIcon(CallSummary summary) {
  final isVideo = summary.kind == 'video';
  return switch (summary.status) {
    CallSummaryStatus.missed =>
      isVideo ? Icons.missed_video_call_outlined : Icons.call_missed_outlined,
    CallSummaryStatus.declined => Icons.call_end_outlined,
    CallSummaryStatus.ended =>
      isVideo ? Icons.videocam_outlined : Icons.call_outlined,
  };
}
