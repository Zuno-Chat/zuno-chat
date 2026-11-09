import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../../../../core/matrix/media/attachments/attachment_actions.dart';
import '../../../../core/matrix/media/attachments/attachment_cache.dart';
import '../../../../core/matrix/media/playable_media_file.dart';
import '../../../../core/matrix/media/voice/voice_message.dart';
import '../../../../core/matrix/media/voice/voice_recording.dart';
import '../../../../core/platform/platform_capabilities.dart';
import '../message_bubble.dart';
import '../voice_player.dart';

class VoiceMessage extends StatelessWidget {
  final Event event;
  final bool own;
  final Widget meta;

  const VoiceMessage({
    super.key,
    required this.event,
    required this.own,
    required this.meta,
  });

  Future<File> _load(ValueSetter<bool> loading) async {
    final downloads = !await isAttachmentCached(
      attachmentCacheKey(event, thumbnail: false),
    );
    if (downloads) loading(true);
    final File cached;
    try {
      cached = await cachedAttachmentFile(event);
    } finally {
      if (downloads) loading(false);
    }
    return playableMediaFile(
      cached,
      mimetype: attachmentMimeType(event) ?? await _sniffedType(cached),
      fileName: attachmentFileName(event),
      fallbackExtension: '.ogg',
      capabilities: ambientCapabilities,
    );
  }

  Future<String?> _sniffedType(File file) async => sniffAudioMimeType(
    Uint8List.fromList(
      await file.openRead(0, 12).expand((chunk) => chunk).toList(),
    ),
  );

  @override
  Widget build(BuildContext context) => VoicePlayer(
    load: _load,
    duration: voiceMessageDuration(event),
    waveform: _drawnBars(event),
    muted: bubbleMuted(Theme.of(context), own: own),
    meta: meta,
  );
}

const _waveformBars = 50;

List<int>? _drawnBars(Event event) {
  final samples = voiceMessageWaveform(event);
  if (samples == null || samples.length <= _waveformBars) return samples;
  return resampleWaveform([for (final sample in samples) sample / 1024]);
}

double normalizedAmplitude(double db) {
  const floor = -45.0;
  final clamped = db.clamp(floor, 0.0);
  return (clamped - floor) / -floor;
}

List<int> resampleWaveform(
  List<double> samples, {
  int buckets = _waveformBars,
}) {
  if (samples.isEmpty) return List.filled(buckets, 0);
  final result = <int>[];
  for (var i = 0; i < buckets; i++) {
    final start = (i * samples.length / buckets).floor();
    final end = ((i + 1) * samples.length / buckets).floor().clamp(
      start + 1,
      samples.length,
    );
    final slice = samples.sublist(start, end);
    final avg = slice.reduce((a, b) => a + b) / slice.length;
    result.add((avg * 1024).round().clamp(0, 1024));
  }
  return result;
}
