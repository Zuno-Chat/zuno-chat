import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/ui/search_field.dart';
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
  late final _searchable = [
    for (final user in widget.members)
      (
        user: user,
        name: user.calcDisplayname().toLowerCase(),
        id: withoutServer(user.id).toLowerCase(),
      ),
  ];
  late List<User> _matches = widget.members;

  void _search(String query) {
    final needle = query.trim().toLowerCase();
    setState(() {
      _matches = needle.isEmpty
          ? widget.members
          : [
              for (final entry in _searchable)
                if (entry.name.contains(needle) || entry.id.contains(needle))
                  entry.user,
            ];
    });
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
            SheetTitle(context.l10n.roomInfoMembers),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SearchField(
                hint: context.l10n.roomInfoSearchMembers,
                autofocus: true,
                onChanged: _search,
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
