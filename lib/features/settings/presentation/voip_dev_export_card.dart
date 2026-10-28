import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/push/ring/ring_channel.dart';
import '../../../core/security/sensitive_clipboard.dart';
import '../../../core/ui/card_group.dart';

String voipDevExportJson(VoipDevExport export) =>
    jsonEncode({'token': export.token, 'kid': export.kid, 'key': export.key});

class VoipDevExportCard extends StatefulWidget {
  const VoipDevExportCard({super.key, this.channel = const RingChannel()});

  final RingChannel channel;

  @override
  State<VoipDevExportCard> createState() => _VoipDevExportCardState();
}

class _VoipDevExportCardState extends State<VoipDevExportCard> {
  late final Future<VoipDevExport?> _export = widget.channel.devExport();

  Future<void> _copy(VoipDevExport export) async {
    await SensitiveClipboard.instance.copy(voipDevExportJson(export));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.settingsCopiedSensitive)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VoipDevExport?>(
      future: _export,
      builder: (context, snapshot) {
        final export = snapshot.data;
        if (export == null) return const SizedBox.shrink();
        final l10n = context.l10n;
        return CardGroup(
          title: l10n.settingsVoipTestValues,
          children: [
            ListTile(
              leading: const Icon(Icons.science_outlined),
              title: Text(l10n.settingsVoipDevOnly),
              subtitle: Text(l10n.settingsVoipDevOnlySubtitle),
            ),
            ListTile(
              title: Text(l10n.settingsVoipToken),
              subtitle: Text(export.token),
            ),
            ListTile(
              title: Text(l10n.settingsVoipKeyId),
              subtitle: Text('${export.kid}'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(l10n.settingsVoipCopy),
              onTap: () => _copy(export),
            ),
          ],
        );
      },
    );
  }
}
