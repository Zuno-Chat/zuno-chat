import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/security/security_emphasis.dart';
import 'share_target_list.dart';

const maxForwardTargets = 5;

Future<List<Room>?> pickForwardTargets(
  BuildContext context, {
  required Client client,
  required bool fromEncrypted,
}) => Navigator.of(context).push<List<Room>>(
  MaterialPageRoute(
    builder: (_) =>
        ForwardPickerPage(client: client, fromEncrypted: fromEncrypted),
  ),
);

class ForwardPickerPage extends StatefulWidget {
  final Client client;
  final bool fromEncrypted;

  const ForwardPickerPage({
    required this.client,
    required this.fromEncrypted,
    super.key,
  });

  @override
  State<ForwardPickerPage> createState() => _ForwardPickerPageState();
}

class _ForwardPickerPageState extends State<ForwardPickerPage> {
  final _ticked = <String>{};

  List<Room> _tickedRooms() => [
    for (final room in widget.client.rooms)
      if (_ticked.contains(room.id) && isShareTarget(room)) room,
  ];

  void _toggle(Room room) {
    final ticked = _tickedRooms();
    _ticked.retainAll({for (final room in ticked) room.id});
    if (_ticked.remove(room.id)) {
      setState(() {});
      return;
    }
    if (ticked.length >= maxForwardTargets) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(context.l10n.shareForwardLimit(maxForwardTargets)),
          ),
        );
      return;
    }
    setState(() => _ticked.add(room.id));
  }

  String? _note(AppLocalizations l10n, List<Room> ticked) {
    if (!widget.fromEncrypted) return null;
    final open = ticked.where((room) => !room.encrypted).length;
    if (open == 0) return null;
    return ticked.length == 1
        ? l10n.shareForwardOneNotEncrypted
        : l10n.shareForwardSomeNotEncrypted(open);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.shareForwardTitle)),
      body: StreamBuilder<SyncUpdate>(
        stream: widget.client.onSync.stream,
        builder: (context, _) {
          final ticked = _tickedRooms();
          final note = _note(l10n, ticked);
          return Column(
            children: [
              Expanded(
                child: ShareTargetList(
                  client: widget.client,
                  onTap: _toggle,
                  trailing: (room) => Checkbox(
                    value: _ticked.contains(room.id),
                    onChanged: (_) => _toggle(room),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (note != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Icon(
                                notEncryptedIcon,
                                size: 18,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(note)),
                            ],
                          ),
                        ),
                      FilledButton(
                        onPressed: ticked.isEmpty
                            ? null
                            : () => Navigator.of(context).pop(ticked),
                        child: Text(l10n.commonSend),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
