import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../../../../core/errors/best_effort.dart';
import '../../../../core/errors/caught_errors.dart';
import '../../../../core/format/human_units.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/matrix/attachment_actions.dart';
import '../../../../core/matrix/attachment_cache.dart';
import '../../../../core/matrix/playable_media_file.dart';
import '../../../../core/matrix/voice_audio_session.dart';
import '../../../../core/matrix/voice_message.dart';
import '../../../../core/matrix/voice_recording.dart';
import '../../../../core/platform/platform_capabilities.dart';
import '../message_bubble.dart';

class VoiceMessage extends ConsumerStatefulWidget {
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
  ConsumerState<VoiceMessage> createState() => _VoiceMessageState();
}

const _waveformBars = 50;

List<int>? _drawnBars(Event event) {
  final samples = voiceMessageWaveform(event);
  if (samples == null || samples.length <= _waveformBars) return samples;
  return resampleWaveform([for (final sample in samples) sample / 1024]);
}

class _VoiceMessageState extends ConsumerState<VoiceMessage>
    implements VoicePlayback {
  final _player = AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
  );
  final _subscriptions = <StreamSubscription<Object?>>[];
  late final VoiceAudioSession _audio;
  bool _playing = false;
  bool _inProgress = false;
  bool _loaded = false;
  bool _loading = false;
  bool _starting = false;
  Future<bool>? _loadingFile;
  Duration _position = Duration.zero;
  Duration? _duration;
  List<int>? _waveform;

  String get _cacheKey => attachmentCacheKey(widget.event, thumbnail: false);

  @override
  void initState() {
    super.initState();
    _audio = ref.read(voiceAudioSessionProvider);
    _duration = voiceMessageDuration(widget.event);
    _waveform = _drawnBars(widget.event);
    _subscriptions.addAll([
      _player.playerStateStream.listen(_onPlayerState),
      _player
          .createPositionStream(
            minPeriod: const Duration(milliseconds: 100),
            maxPeriod: const Duration(milliseconds: 200),
          )
          .listen((position) {
            if (mounted && _playing) setState(() => _position = position);
          }),
      _player.durationStream.listen((duration) {
        if (mounted && duration != null) setState(() => _duration = duration);
      }),
      _player.errorStream.listen(_playerFailed),
    ]);
  }

  void _onPlayerState(PlayerState state) {
    final finished = state.processingState == ProcessingState.completed;
    if (finished || state.processingState == ProcessingState.idle) {
      unawaited(_audio.endPlayback(this));
    }
    if (finished) {
      _inProgress = false;
      if (state.playing) unawaited(_rewind());
    }
    final playing = state.playing && !finished;
    if (!mounted) return;
    setState(() {
      _playing = playing;
      if (finished) _position = Duration.zero;
    });
  }

  Future<void> _rewind() async {
    await _player.pause();
    await _player.seek(Duration.zero);
  }

  void _playerFailed(PlayerException error) {
    _loaded = false;
    _inProgress = false;
    if (!_starting) {
      reportCaught('voice message player', error, StackTrace.current);
    }
  }

  @override
  void didUpdateWidget(VoiceMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.event, widget.event)) {
      _waveform = _drawnBars(widget.event);
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_release());
    super.dispose();
  }

  Future<void> _release() async {
    await runBestEffort(_player.dispose, label: 'release voice message player');
    await _audio.endPlayback(this);
  }

  Future<void> _toggle() async {
    if (_playing) {
      await pause();
    } else {
      await _start();
    }
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    if (!_player.playing) await _audio.endPlayback(this);
  }

  Future<void> _start({Duration? at}) async {
    if (!_loaded && !await _load()) return;
    if (at != null) await _seek(at);
    if (!mounted) return;
    await _audio.beginPlayback(this);
    _inProgress = true;
    unawaited(_player.play());
  }

  Future<bool> _load() =>
      _loadingFile ??= _loadFile().whenComplete(() => _loadingFile = null);

  Future<bool> _loadFile() async {
    final downloads = !await isAttachmentCached(_cacheKey);
    if (downloads && mounted) setState(() => _loading = true);
    final File cached;
    try {
      cached = await fetchCachedAttachmentFile(
        _cacheKey,
        () async => (await widget.event.downloadAndDecryptAttachment()).bytes,
      );
    } catch (e, s) {
      reportCaught('load voice message', e, s);
      _didNotLoad();
      return false;
    } finally {
      if (downloads && mounted) setState(() => _loading = false);
    }
    if (!mounted) return false;
    _starting = true;
    try {
      final file = await playableMediaFile(
        cached,
        mimetype:
            attachmentMimeType(widget.event) ?? await _sniffedType(cached),
        fileName: attachmentFileName(widget.event),
        fallbackExtension: '.ogg',
        capabilities: ambientCapabilities,
      );
      if (!mounted) return false;
      await _player.setFilePath(file.path);
      _loaded = true;
      return mounted;
    } catch (e, s) {
      if (!mounted) return false;
      reportCaught('play voice message', e, s);
      _didNotLoad();
      return false;
    } finally {
      _starting = false;
    }
  }

  Future<String?> _sniffedType(File file) async => sniffAudioMimeType(
    Uint8List.fromList(
      await file.openRead(0, 12).expand((chunk) => chunk).toList(),
    ),
  );

  void _didNotLoad() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.chatVoiceMessageDidNotLoad)),
    );
  }

  Future<void> _seek(Duration position) async {
    await _player.seek(position);
    if (mounted) setState(() => _position = position);
  }

  Future<void> _seekTo(double ratio) async {
    final total = _duration ?? Duration.zero;
    if (total == Duration.zero) return;
    final target = Duration(
      milliseconds: (ratio * total.inMilliseconds).round(),
    );
    if (_inProgress) {
      await _seek(target);
    } else {
      await _start(at: target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration ?? Duration.zero;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final waveform = _waveform;

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
                      _playing ? Icons.pause : Icons.play_arrow,
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
                      _playing || _position > Duration.zero
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
