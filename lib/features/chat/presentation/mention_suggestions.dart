import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/mxc_avatar.dart';
import 'mention_query.dart';

const _maxSuggestions = 30;
const _minQueryLength = 2;

class MentionSuggestions extends StatefulWidget {
  final Room room;
  final TextEditingController controller;
  final Future<List<User>> Function()? loadMembers;

  const MentionSuggestions({
    required this.room,
    required this.controller,
    this.loadMembers,
    super.key,
  });

  @override
  State<MentionSuggestions> createState() => _MentionSuggestionsState();
}

class _MentionSuggestionsState extends State<MentionSuggestions> {
  List<User>? _everyone;
  Future<void>? _fetching;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  MentionQuery? get _query {
    final selection = widget.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final query = mentionQueryAt(widget.controller.text, selection.baseOffset);
    if (query == null || query.text.length < _minQueryLength) return null;
    return query;
  }

  void _changed() {
    if (!mounted) return;
    if (_query != null) _ensureEveryone();
    setState(() {});
  }

  void _ensureEveryone() {
    if (_everyone != null ||
        _fetching != null ||
        widget.room.participantListComplete) {
      return;
    }
    _fetching = (widget.loadMembers ?? _fetchEveryone)().then((users) {
      if (mounted) setState(() => _everyone = users);
    }, onError: (_) => _fetching = null);
  }

  Future<List<User>> _fetchEveryone() async {
    final room = widget.room;
    var members = const <User>[];
    Object? failure;
    await room.client.database.transaction(() async {
      try {
        members = await room.requestParticipants(
          const [Membership.join],
          true,
          true,
        );
      } catch (e) {
        failure = e;
      }
    });
    if (failure != null) throw failure!;
    return members;
  }

  List<User> _candidates() {
    final ownId = widget.room.client.userID;
    final byId = <String, User>{
      for (final user in widget.room.getParticipants([Membership.join]))
        user.id: user,
      for (final user in _everyone ?? const <User>[])
        if (user.membership == Membership.join) user.id: user,
    };
    byId.remove(ownId);
    return byId.values.toList();
  }

  void _pick(User user, MentionQuery query) {
    final result = applyMention(
      widget.controller.text,
      query,
      cursor: widget.controller.selection.baseOffset,
      insert: mentionInsertText(user),
    );
    widget.controller.value = TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.cursor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _query;
    if (query == null) return const SizedBox.shrink();
    final matches = mentionMatches(
      _candidates(),
      query.text,
      limit: _maxSuggestions,
    );
    if (matches.isEmpty) return const SizedBox.shrink();

    return Material(
      elevation: 4,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: matches.length,
          itemBuilder: (context, index) {
            final user = matches[index];
            return ListTile(
              dense: true,
              leading: MxcAvatar(
                client: widget.room.client,
                avatarUrl: user.avatarUrl,
                fallbackText: user.calcDisplayname(),
                radius: 16,
              ),
              title: Text(user.calcDisplayname()),
              subtitle: Text(withoutServer(user.id)),
              onTap: () => _pick(user, query),
            );
          },
        ),
      ),
    );
  }
}
