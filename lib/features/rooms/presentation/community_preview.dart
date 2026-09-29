import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/room_title.dart';
import '../../../core/ui/line_strut.dart';
import 'last_message_preview.dart';

class CommunityPreview extends StatelessWidget {
  final Room? room;

  const CommunityPreview({required this.room, super.key});

  @override
  Widget build(BuildContext context) {
    final strut = inheritedLineStrut(context);
    final room = this.room;
    if (room == null) return Text('No rooms joined yet', strutStyle: strut);

    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.45),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: roomTitle(room),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const TextSpan(text: ' ·'),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              strutStyle: strut,
            ),
          ),
          Flexible(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: MediaQuery.textScalerOf(context).scale(4),
              ),
              child: LastMessagePreview(room: room, event: room.lastEvent),
            ),
          ),
        ],
      ),
    );
  }
}
