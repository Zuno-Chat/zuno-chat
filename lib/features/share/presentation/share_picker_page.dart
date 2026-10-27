import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import 'share_target_list.dart';

class SharePickerPage extends StatelessWidget {
  final Client client;
  final Widget Function(Room room) destination;

  const SharePickerPage({
    required this.client,
    required this.destination,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.shareTo)),
      body: ShareTargetList(
        client: client,
        onTap: (room) => Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => destination(room))),
      ),
    );
  }
}
