import 'package:flutter/material.dart';

import '../../../core/ui/timeline_pill.dart';

class RoomUpdateTile extends StatelessWidget {
  final List<String> lines;

  const RoomUpdateTile({super.key, required this.lines});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
      child: Column(
        spacing: 4,
        children: [for (final line in lines) TimelinePill(line)],
      ),
    );
  }
}
