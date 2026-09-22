import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../../../../core/errors/best_effort.dart';
import '../../../../core/matrix/attachment_cache.dart';
import '../../../../core/matrix/voice_message.dart';
import '../../data/message_kinds.dart';
import '../message_bubble.dart';

class VoiceMessage extends StatefulWidget {
  final Event event;
  final bool own;
  final Widget meta;

  const VoiceMessage({
    super.key,
    required this.event,
    required this.own,
    required this.meta,
  });

  @override
  State<VoiceMessage> createState() => _VoiceMessageState();
}

class _VoiceMessageState extends State<VoiceMessage> {
  final _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _loading = false;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<void>? _completeSub;

  String get _cacheKey => '${widget.event.eventId}:audio';

  @override
  void initState() {
    super.initState();
    _duration = voiceMessageDuration(widget.event);
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _state = state);
    });
    _positionSub = _player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _durationSub = _player.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _position = Duration.zero);
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
      return;
    }
    var bytes = AttachmentCache.instance.get(_cacheKey);
    if (bytes == null) {
      setState(() => _loading = true);
      try {
        final file = await widget.event.downloadAndDecryptAttachment();
        bytes = file.bytes;
        AttachmentCache.instance.put(_cacheKey, bytes);
      } catch (e) {
        logCaught('load voice message', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Voice message did not load. Try again.'),
            ),
          );
        }
        return;
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
    await _player.play(
      BytesSource(
        bytes,
        mimeType: widget.event.infoMap.tryGet<String>('mimetype'),
      ),
    );
  }

  Future<void> _seekTo(double ratio) async {
    final total = _duration ?? Duration.zero;
    if (total == Duration.zero) return;
    if (_state == PlayerState.stopped) await _toggle();
    await _player.seek(
      Duration(milliseconds: (ratio * total.inMilliseconds).round()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration ?? Duration.zero;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final isPlaying = _state == PlayerState.playing;
    final waveform = voiceMessageWaveform(widget.event);

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = bubbleMuted(theme, own: widget.own);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Material(
            color: colors.primaryContainer,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: _loading
                ? Padding(
                    padding: const EdgeInsets.all(11),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.onPrimaryContainer,
                    ),
                  )
                : InkWell(
                    onTap: _toggle,
                    child: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              waveform == null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                        ),
                      ),
                    )
                  : _WaveformBars(
                      samples: waveform,
                      progress: progress,
                      onSeek: _seekTo,
                    ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatDuration(
                      isPlaying || _position > Duration.zero
                          ? _position
                          : total,
                    ),
                    style: theme.textTheme.labelSmall!.copyWith(color: muted),
                  ),
                  widget.meta,
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WaveformBars extends StatelessWidget {
  final List<int> samples;
  final double progress;
  final ValueChanged<double> onSeek;

  const _WaveformBars({
    required this.samples,
    required this.progress,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => onSeek(
          (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0),
        ),
        child: CustomPaint(
          size: const Size(double.infinity, 24),
          painter: _WaveformPainter(
            samples: samples,
            progress: progress,
            played: colors.primary,
            unplayed: colors.outline,
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<int> samples;
  final double progress;
  final Color played;
  final Color unplayed;

  const _WaveformPainter({
    required this.samples,
    required this.progress,
    required this.played,
    required this.unplayed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final slot = size.width / samples.length;
    final barWidth = (slot - 1).clamp(1.0, 3.0);
    final paint = Paint();
    for (var i = 0; i < samples.length; i++) {
      final height = (samples[i] / 1024 * 22).clamp(2.0, 22.0);
      paint.color = i / samples.length <= progress ? played : unplayed;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(slot * i + slot / 2, size.height / 2),
            width: barWidth,
            height: height,
          ),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.played != played ||
      old.unplayed != unplayed ||
      !identical(old.samples, samples);
}

double normalizedAmplitude(double db) {
  const floor = -45.0;
  final clamped = db.clamp(floor, 0.0);
  return (clamped - floor) / -floor;
}

List<int> resampleWaveform(List<double> samples, {int buckets = 50}) {
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
