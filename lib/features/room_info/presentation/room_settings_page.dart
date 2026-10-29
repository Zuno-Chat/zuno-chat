import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/display_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/avatar_photo.dart';
import '../../../core/matrix/communities.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/optimistic_room_state.dart';
import '../../../core/matrix/room_access.dart';
import '../../../core/matrix/room_avatar.dart';
import '../../../core/matrix/room_history.dart';
import '../../../core/matrix/room_name_check.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import '../../../core/ui/confirm_dialog.dart';
import '../../../core/ui/edit_text_dialog.dart';
import '../../../core/ui/inline_feedback.dart';
import '../../../core/ui/notice.dart';
import '../../../core/ui/sheet.dart';

String _historyVisibilityLabel(
  AppLocalizations l10n,
  HistoryVisibility visibility,
) => switch (visibility) {
  HistoryVisibility.worldReadable => l10n.roomInfoHistoryAnyone,
  HistoryVisibility.shared => l10n.roomInfoHistoryShared,
  HistoryVisibility.invited => l10n.roomInfoHistoryInvited,
  HistoryVisibility.joined => l10n.roomInfoHistoryJoined,
};

const roomNameMaxLength = 50;
const roomTopicMaxLength = 250;
const roomAliasMaxLength = 50;

enum _Field {
  avatar,
  name,
  topic,
  alias,
  history,
  access;

  bool shownIn(Room room) => switch (this) {
    avatar || access => !room.isDirectChat,
    alias || history => !room.isSpace,
    name || topic => true,
  };

  bool editableIn(Room room) =>
      shownIn(room) &&
      switch (this) {
        avatar => room.canChangeStateEvent(EventTypes.RoomAvatar),
        name => room.canChangeStateEvent(EventTypes.RoomName),
        topic => room.canChangeStateEvent(EventTypes.RoomTopic),
        alias => room.canChangeStateEvent(EventTypes.RoomCanonicalAlias),
        history => room.canChangeHistoryVisibility,
        access => canChangeRoomAccess(room),
      };
}

bool canEditRoomSettings(Room room) =>
    !room.isDirectChat && _Field.values.any((field) => field.editableIn(room));

class RoomSettingsPage extends StatefulWidget {
  final Room room;

  const RoomSettingsPage({required this.room, super.key});

  @override
  State<RoomSettingsPage> createState() => _RoomSettingsPageState();
}

class _RoomSettingsPageState extends State<RoomSettingsPage> {
  late final bool _community = widget.room.isSpace;
  final _saving = <_Field>{};

  String _nameLabel(AppLocalizations l10n) =>
      _community ? l10n.communitiesCommunityName : l10n.roomsRoomName;

  String _topicLabel(AppLocalizations l10n) =>
      _community ? l10n.roomInfoDescription : l10n.roomInfoTopic;

  Future<void> _save(
    _Field field, {
    required String label,
    @displayText required String success,
    @displayText required String failure,
    required Future<void> Function() write,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() => _saving.add(field));
    try {
      await write();
      messenger.say(success);
    } on RoomListingRefused {
      messenger.say(l10n.matrixRoomListingRefused);
    } catch (e, s) {
      reportCaught(label, e, s);
      messenger.sayFailed(l10n, e, failed: failure);
    } finally {
      if (mounted) setState(() => _saving.remove(field));
    }
  }

  Future<void> _editName() async {
    final room = widget.room;
    final l10n = context.l10n;
    final name = await showEditTextDialog(
      context,
      title: _nameLabel(l10n),
      initialValue: room.name,
      maxLength: roomNameMaxLength,
      allowEmpty: false,
      validator: (name) => roomNameError(l10n, name),
    );
    if (name == null || name.isEmpty || name == room.name || !mounted) return;

    await _save(
      _Field.name,
      label: 'save name',
      success: _community
          ? l10n.roomInfoCommunityNameUpdated
          : l10n.roomInfoRoomNameUpdated,
      failure: _community
          ? l10n.roomInfoCommunityNameNotSaved
          : l10n.roomInfoRoomNameNotSaved,
      write: () async {
        await room.setName(name);
        applyOptimisticRoomState(room, EventTypes.RoomName, {'name': name});
      },
    );
  }

  Future<void> _editTopic() async {
    final room = widget.room;
    final l10n = context.l10n;
    final topic = await showEditTextDialog(
      context,
      title: _topicLabel(l10n),
      initialValue: room.topic,
      maxLines: 3,
      maxLength: roomTopicMaxLength,
    );
    if (topic == null || topic == room.topic || !mounted) return;

    await _save(
      _Field.topic,
      label: 'save topic',
      success: _community
          ? l10n.roomInfoDescriptionUpdated
          : l10n.roomInfoTopicUpdated,
      failure: _community
          ? l10n.roomInfoDescriptionNotSaved
          : l10n.roomInfoTopicNotSaved,
      write: () async {
        await room.setDescription(topic);
        applyOptimisticRoomState(room, EventTypes.RoomTopic, {'topic': topic});
      },
    );
  }

  Future<void> _editAlias() async {
    final room = widget.room;
    final l10n = context.l10n;
    final domain = room.client.userID!.domain;
    final current = room.canonicalAlias.localpart ?? '';
    final localpart = await showEditTextDialog(
      context,
      title: l10n.roomInfoMainAddress,
      initialValue: current,
      prefixText: '#',
      maxLength: roomAliasMaxLength,
    );
    if (localpart == null || localpart == current || !mounted) return;

    await _save(
      _Field.alias,
      label: 'save main address',
      success: l10n.roomInfoMainAddressUpdated,
      failure: l10n.roomInfoMainAddressNotSaved,
      write: () => localpart.isEmpty
          ? _clearAlias(room)
          : _setAlias(room, '#$localpart:$domain'),
    );
  }

  Future<void> _setAlias(Room room, String alias) async {
    await room.setCanonicalAlias(alias);
    applyOptimisticRoomState(room, EventTypes.RoomCanonicalAlias, {
      'alias': alias,
    });
  }

  Future<void> _clearAlias(Room room) async {
    final previous = room.canonicalAlias;
    if (previous.isNotEmpty) {
      try {
        await room.client.deleteRoomAlias(previous);
      } on MatrixException catch (e) {
        if (e.error != MatrixError.M_NOT_FOUND) rethrow;
      }
    }
    await room.client.setRoomStateWithKey(
      room.id,
      EventTypes.RoomCanonicalAlias,
      '',
      {},
    );
    applyOptimisticRoomState(room, EventTypes.RoomCanonicalAlias, {});
  }

  Future<void> _changeHistoryVisibility() async {
    final room = widget.room;
    final l10n = context.l10n;
    final current = historyVisibilityOf(room);
    final chosen = await showChoiceSheet(
      context,
      current: current,
      header: l10n.roomInfoHistoryFromNow,
      choices: [
        for (final visibility in historyChoices(room))
          SheetChoice(
            visibility,
            label: _historyVisibilityLabel(l10n, visibility),
          ),
      ],
    );
    if (chosen == null || chosen == current || !mounted) return;

    await _save(
      _Field.history,
      label: 'save history visibility',
      success: l10n.roomInfoHistorySettingUpdated,
      failure: l10n.roomInfoHistorySettingNotSaved,
      write: () async {
        await room.setHistoryVisibility(chosen);
        applyOptimisticRoomState(room, EventTypes.HistoryVisibility, {
          'history_visibility': chosen.text,
        });
      },
    );
  }

  Future<void> _changeAvatar() async {
    final room = widget.room;
    final action = await chooseAvatarAction(
      context,
      canRemove: room.avatar != null,
    );
    if (action == null || !mounted) return;

    setState(() => _saving.add(_Field.avatar));
    await applyAvatarAction(
      context,
      action,
      nativeImplementations: room.client.nativeImplementations,
      apply: (photo) => setRoomAvatar(room, photo),
      label: 'update room photo',
    );
    if (mounted) setState(() => _saving.remove(_Field.avatar));
  }

  Future<void> _changeAccess() async {
    final room = widget.room;
    final l10n = context.l10n;
    final current = roomAccessOf(room);
    final communities = _community ? const <Room>[] : communitiesOf(room);
    final inCommunity = !_community && room.spaceParents.isNotEmpty;
    final chosen = await showChoiceSheet(
      context,
      current: current,
      choices: [
        for (final access in [
          if (!inCommunity) RoomAccess.public,
          if (communities.isNotEmpty) RoomAccess.community,
          if (inCommunity) RoomAccess.askToJoin,
          RoomAccess.private,
        ])
          SheetChoice(
            access,
            label: access.label(l10n),
            subtitle: access.description(l10n),
          ),
      ],
    );
    if (chosen == null || chosen == current || !mounted) return;

    final confirmed = await _confirmAccessChange(chosen);
    if (!confirmed || !mounted) return;

    await _save(
      _Field.access,
      label: 'save access',
      success: _community
          ? l10n.roomInfoCommunityAccessUpdated
          : l10n.roomInfoRoomAccessUpdated,
      failure: _community
          ? l10n.roomInfoCommunityAccessNotSaved
          : l10n.roomInfoRoomAccessNotSaved,
      write: () => setRoomAccess(room, chosen),
    );
  }

  Future<bool> _confirmAccessChange(RoomAccess chosen) {
    final l10n = context.l10n;
    final (title, action) = switch (chosen) {
      RoomAccess.public => (
        _community
            ? l10n.roomInfoMakeCommunityPublicTitle
            : l10n.roomInfoMakeRoomPublicTitle,
        l10n.roomInfoMakePublic,
      ),
      RoomAccess.community => (
        l10n.roomInfoOpenToCommunityTitle,
        l10n.roomInfoOpenToMembers,
      ),
      RoomAccess.askToJoin => (
        l10n.roomInfoLetMembersAskTitle,
        l10n.roomInfoLetThemAsk,
      ),
      RoomAccess.private => (
        _community
            ? l10n.roomInfoMakeCommunityPrivateTitle
            : l10n.roomInfoMakeRoomPrivateTitle,
        l10n.roomInfoMakePrivate,
      ),
    };
    return confirm(
      context,
      title: title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in _accessConsequences(l10n, chosen, _community))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(l10n.roomInfoAccessBullet(line)),
            ),
        ],
      ),
      confirmLabel: action,
    );
  }

  Widget _tile(
    _Field field, {
    required Widget leading,
    @displayText required String title,
    Widget? subtitle,
    required VoidCallback edit,
  }) => _SettingTile(
    leading: leading,
    title: title,
    subtitle: subtitle,
    saving: _saving.contains(field),
    onEdit: field.editableIn(widget.room) ? edit : null,
  );

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final l10n = context.l10n;
    final aliasLocalpart = room.canonicalAlias.localpart;
    bool shown(_Field field) => field.shownIn(room);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _community
              ? l10n.roomInfoCommunitySettings
              : l10n.roomInfoRoomSettings,
        ),
      ),
      body: CardListView(
        children: [
          CardGroup(
            title: _community
                ? l10n.roomInfoCommunityInfo
                : l10n.roomInfoRoomInfo,
            children: [
              if (shown(_Field.avatar))
                _tile(
                  _Field.avatar,
                  leading: MxcAvatar(
                    client: room.client,
                    avatarUrl: room.avatar,
                    fallbackText: roomTitle(room, l10n),
                    toneSeed: roomToneSeed(room),
                    radius: 20,
                    shape: AvatarShape.forRoom(room),
                  ),
                  title: _community
                      ? l10n.roomInfoCommunityPhoto
                      : l10n.roomInfoRoomPhoto,
                  edit: _changeAvatar,
                ),
              _tile(
                _Field.name,
                leading: const Icon(Icons.title_outlined),
                title: _nameLabel(l10n),
                subtitle: Text(
                  room.name.isEmpty ? l10n.roomInfoNotSet : room.name,
                ),
                edit: _editName,
              ),
              _tile(
                _Field.topic,
                leading: const Icon(Icons.notes_outlined),
                title: _topicLabel(l10n),
                subtitle: Text(
                  room.topic.isEmpty ? l10n.roomInfoNotSet : room.topic,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                edit: _editTopic,
              ),
              if (shown(_Field.alias))
                _tile(
                  _Field.alias,
                  leading: const Icon(Icons.tag_outlined),
                  title: l10n.roomInfoMainAddress,
                  subtitle: Text(
                    aliasLocalpart == null
                        ? l10n.roomInfoNotSet
                        : '#$aliasLocalpart',
                  ),
                  edit: _editAlias,
                ),
            ],
          ),
          CardGroup(
            title: l10n.roomInfoPrivacy,
            children: [
              if (shown(_Field.history))
                _tile(
                  _Field.history,
                  leading: const Icon(Icons.history_outlined),
                  title: l10n.roomInfoWhoCanReadHistory,
                  subtitle: Text(
                    _historyVisibilityLabel(l10n, historyVisibilityOf(room)),
                  ),
                  edit: _changeHistoryVisibility,
                ),
              if (shown(_Field.access))
                _tile(
                  _Field.access,
                  leading: const Icon(Icons.public_outlined),
                  title: _community
                      ? l10n.roomInfoCommunityAccess
                      : l10n.roomInfoRoomAccess,
                  subtitle: Text(roomAccessOf(room).label(l10n)),
                  edit: _changeAccess,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final Widget? subtitle;
  final bool saving;
  final VoidCallback? onEdit;

  const _SettingTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.saving,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    leading: leading,
    title: Text(title),
    subtitle: subtitle,
    trailing: saving
        ? const InlineSpinner()
        : onEdit == null
        ? const SizedBox.shrink()
        : const Icon(Icons.chevron_right_outlined),
    onTap: saving ? null : onEdit,
  );
}

List<String> _accessConsequences(
  AppLocalizations l10n,
  RoomAccess access,
  bool community,
) => switch (access) {
  RoomAccess.public => [
    l10n.roomInfoAccessFindable,
    l10n.roomInfoAccessJoinFree,
    community
        ? l10n.roomInfoAccessCommunityRoomsKeep
        : l10n.roomInfoAccessHistoryDepends,
  ],
  RoomAccess.community => [
    l10n.roomInfoAccessCommunityMembersJoin,
    l10n.roomInfoAccessNotListed,
    l10n.roomInfoAccessMembersStay,
  ],
  RoomAccess.askToJoin => [
    l10n.roomInfoAccessCommunitySeesAndAsks,
    l10n.roomInfoAccessModeratorsDecide,
    l10n.roomInfoAccessMembersStay,
  ],
  RoomAccess.private => [
    community
        ? l10n.roomInfoAccessCommunityLeavesList
        : l10n.roomInfoAccessRoomLeavesList,
    l10n.roomInfoAccessNeedInvite,
    l10n.roomInfoAccessMembersStay,
  ],
};
