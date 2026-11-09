import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/files/file_system.dart';
import '../../../core/files/picked_file.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/media/voice/voice_recording.dart';
import 'voice_player.dart';

class KeptRecording extends StatefulWidget {
  final VoiceClip clip;
  final VoidCallback onDelete;

  const KeptRecording({super.key, required this.clip, required this.onDelete});

  @override
  State<KeptRecording> createState() => _KeptRecordingState();
}

class _KeptRecordingState extends State<KeptRecording> {
  File? _copy;

  Future<File> _load(ValueSetter<bool> _) async {
    final existing = _copy;
    if (existing != null) return existing;
    final copy = _copy = fileSystem.file(await newVoiceFilePath('ogg'));
    await copy.writeAsBytes(widget.clip.bytes);
    if (!mounted) await discardTemporaryCopy(copy.path);
    return copy;
  }

  @override
  void dispose() {
    final copy = _copy;
    if (copy != null) unawaited(discardTemporaryCopy(copy.path));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: context.l10n.commonDelete,
            onPressed: widget.onDelete,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: VoicePlayer(
                load: _load,
                duration: clip.duration,
                waveform: clip.waveform,
                muted: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
