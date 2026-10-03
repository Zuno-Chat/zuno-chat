import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/push/voip/voip_channel.dart';
import '../../../core/security/sensitive_clipboard.dart';
import '../../../core/ui/card_group.dart';

String voipDevExportJson(VoipDevExport export) =>
    jsonEncode({'token': export.token, 'kid': export.kid, 'key': export.key});

class VoipDevExportCard extends StatefulWidget {
  const VoipDevExportCard({super.key, this.channel = const VoipChannel()});

  final VoipChannel channel;

  @override
  State<VoipDevExportCard> createState() => _VoipDevExportCardState();
}

class _VoipDevExportCardState extends State<VoipDevExportCard> {
  late final Future<VoipDevExport?> _export = widget.channel.devExport();

  Future<void> _copy(VoipDevExport export) async {
    await SensitiveClipboard.instance.copy(voipDevExportJson(export));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied. Clears from the clipboard in 90 seconds.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VoipDevExport?>(
      future: _export,
      builder: (context, snapshot) {
        final export = snapshot.data;
        if (export == null) return const SizedBox.shrink();
        return CardGroup(
          title: 'Call push test values',
          children: [
            const ListTile(
              leading: Icon(Icons.science_outlined),
              title: Text('Development build only'),
              subtitle: Text(
                'These let a test tool on your computer ring this device. '
                'Anyone holding them can do the same until the next sign-in.',
              ),
            ),
            ListTile(
              title: const Text('Call push token'),
              subtitle: Text(export.token),
            ),
            ListTile(
              title: const Text('Key id'),
              subtitle: Text('${export.kid}'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy test values'),
              onTap: () => _copy(export),
            ),
          ],
        );
      },
    );
  }
}
