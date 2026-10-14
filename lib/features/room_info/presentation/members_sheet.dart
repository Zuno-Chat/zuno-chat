import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/security/zuno_text_field.dart';
import '../../../core/ui/sheet.dart';
import 'member_tile.dart';

Future<User?> showMembersSheet(
  BuildContext context, {
  required Room room,
  required List<User> members,
  required bool Function(User user) canManage,
}) => showSheet<User>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) =>
      _MembersSheet(room: room, members: members, canManage: canManage),
);

class _MembersSheet extends StatefulWidget {
  final Room room;
  final List<User> members;
  final bool Function(User user) canManage;

  const _MembersSheet({
    required this.room,
    required this.members,
    required this.canManage,
  });

  @override
  State<_MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends State<_MembersSheet> {
  var _query = '';

  List<User> get _matches {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return widget.members;
    return widget.members
        .where(
          (u) =>
              u.calcDisplayname().toLowerCase().contains(needle) ||
              withoutServer(u.id).toLowerCase().contains(needle),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                context.l10n.roomInfoMembers,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: ZunoTextField(
                autofillHints: null,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: context.l10n.roomInfoSearchMembers,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: matches.isEmpty
                  ? Center(child: Text(context.l10n.roomInfoNoMembersFound))
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final user = matches[index];
                        return MemberTile(
                          room: widget.room,
                          user: user,
                          onTap: widget.canManage(user)
                              ? () => Navigator.of(context).pop(user)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
