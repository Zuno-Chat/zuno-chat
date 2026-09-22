import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../../../../core/errors/best_effort.dart';
import '../../../../core/format/human_units.dart';
import '../../../../core/ui/zuno_theme.dart';
import '../file_name_text.dart';
import '../message_bubble.dart';

class FileMessage extends StatefulWidget {
  final Event event;
  final bool own;
  final Widget meta;

  const FileMessage({
    super.key,
    required this.event,
    required this.own,
    required this.meta,
  });

  @override
  State<FileMessage> createState() => _FileMessageState();
}

class _FileMessageState extends State<FileMessage> {
  bool _downloading = false;

  Future<void> _download() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _downloading = true);
    try {
      final file = await widget.event.downloadAndDecryptAttachment();
      final uri = await FilePicker.saveFile(
        fileName: file.name,
        bytes: file.bytes,
        mimeType: file.mimeType,
      );
      if (uri != null) {
        messenger.showSnackBar(const SnackBar(content: Text('Saved')));
      }
    } catch (e) {
      logCaught('download attachment', e);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.event.infoMap.tryGet<int>('size');
    final theme = Theme.of(context);
    final ink = bubbleInk(theme, own: widget.own);
    final muted = bubbleMuted(theme, own: widget.own);
    return InkWell(
      onTap: _downloading ? null : _download,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                ink.withValues(alpha: 0.09),
                bubbleFill(theme, own: widget.own),
              ),
              borderRadius: BorderRadius.circular(ZunoRadius.small),
            ),
            child: _downloading
                ? Padding(
                    padding: const EdgeInsets.all(11),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ink,
                    ),
                  )
                : Icon(Icons.insert_drive_file_outlined, size: 22, color: ink),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FileNameText(
                  widget.event.body,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      size == null ? '' : formatBytes(size),
                      style: theme.textTheme.labelSmall!.copyWith(color: muted),
                    ),
                    widget.meta,
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
