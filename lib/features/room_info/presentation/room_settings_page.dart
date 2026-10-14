import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/display_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/avatar_photo.dart';
import '../../../core/matrix/communities.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/optimistic_room_state.dart';
import '../../../core/matrix/picker_access.dart';
import '../../../core/matrix/room_access.dart';
import '../../../core/matrix/room_avatar.dart';
import '../../../core/matrix/room_name_check.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/security/zuno_text_field.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import '../../../core/ui/sheet.dart';

enum _AvatarAction { camera, gallery, remove }

String _historyVisibilityLabel(
  AppLocalizations l10n,
  HistoryVisibility visibility,
) => switch (visibility) {
  HistoryVisibility.worldReadable => l10n.roomInfoHistoryAnyone,
  HistoryVisibility.shared => l10n.roomInfoHistoryShared,
  HistoryVisibility.invited => l10n.roomInfoHistoryInvited,
  HistoryVisibility.joined => l10n.roomInfoHistoryJoined,
};

HistoryVisibility _historyVisibilityOf(Room room) =>
    room.historyVisibility ?? HistoryVisibility.shared;

const roomNameMaxLength = 50;
const roomTopicMaxLength = 250;
const roomAliasMaxLength = 50;

class RoomSettingsPage extends StatefulWidget {
  final Room room;

  const RoomSettingsPage({required this.room, super.key});

  @override
  State<RoomSettingsPage> createState() => _RoomSettingsPageState();
}

class _RoomSettingsPageState extends State<RoomSettingsPage> {
  late final bool _community = widget.room.isSpace;
  bool _savingName = false;
  bool _savingTopic = false;
  bool _savingAvatar = false;
  bool _savingAlias = false;
  bool _savingHistoryVisibility = false;
  bool _savingAccess = false;

  String _nameLabel(AppLocalizations l10n) =>
      _community ? l10n.communitiesCommunityName : l10n.roomsRoomName;

  String _topicLabel(AppLocalizations l10n) =>
      _community ? l10n.roomInfoDescription : l10n.roomInfoTopic;

  Future<void> _editName() async {
    final room = widget.room;
    final l10n = context.l10n;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _EditTextFieldDialog(
        title: _nameLabel(l10n),
        initialValue: room.name,
        labelText: _nameLabel(l10n),
        maxLength: roomNameMaxLength,
        validator: (name) => roomNameError(l10n, name),
      ),
    );
    if (name == null || name.isEmpty || name == room.name || !mounted) return;

    await _save(
      setSaving: (saving) => _savingName = saving,
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

  Future<void> _save({
    required void Function(bool saving) setSaving,
    required String label,
    @displayText required String success,
    @displayText required String failure,
    required Future<void> Function() write,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => setSaving(true));
    try {
      await write();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(success)));
      }
    } on RoomListingRefused {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.matrixRoomListingRefused)),
        );
      }
    } catch (e, s) {
      reportCaught(label, e, s);
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(failure)));
      }
    } finally {
      if (mounted) setState(() => setSaving(false));
    }
  }

  Future<void> _editTopic() async {
    final room = widget.room;
    final l10n = context.l10n;
    final topic = await showDialog<String>(
      context: context,
      builder: (_) => _EditTextFieldDialog(
        title: _topicLabel(l10n),
        initialValue: room.topic,
        labelText: _topicLabel(l10n),
        maxLines: 3,
        maxLength: roomTopicMaxLength,
      ),
    );
    if (topic == null || topic == room.topic || !mounted) return;

    await _save(
      setSaving: (saving) => _savingTopic = saving,
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
    final localpart = await showDialog<String>(
      context: context,
      builder: (_) => _EditTextFieldDialog(
        title: l10n.roomInfoMainAddress,
        initialValue: current,
        labelText: l10n.roomInfoMainAddress,
        prefixText: '#',
        maxLength: roomAliasMaxLength,
      ),
    );
    if (localpart == null || localpart == current || !mounted) return;

    await _save(
      setSaving: (saving) => _savingAlias = saving,
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
    final current = _historyVisibilityOf(room);
    final chosen = await showSheet<HistoryVisibility>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            for (final visibility in HistoryVisibility.values)
              ListTile(
                leading: visibility == current
                    ? const Icon(Icons.check_outlined)
                    : const SizedBox(width: 24),
                title: Text(_historyVisibilityLabel(l10n, visibility)),
                onTap: () => Navigator.of(context).pop(visibility),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || chosen == current || !mounted) return;

    await _save(
      setSaving: (saving) => _savingHistoryVisibility = saving,
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
    final l10n = context.l10n;
    final action = await showSheet<_AvatarAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.commonTakePhoto),
              onTap: () => Navigator.of(context).pop(_AvatarAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.commonChooseFromGallery),
              onTap: () => Navigator.of(context).pop(_AvatarAction.gallery),
            ),
            if (room.avatar != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(l10n.commonRemovePhoto),
                onTap: () => Navigator.of(context).pop(_AvatarAction.remove),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingAvatar = true);
    try {
      if (action == _AvatarAction.remove) {
        await setRoomAvatar(room, null);
      } else {
        final picked = await ImagePicker().pickImage(
          source: action == _AvatarAction.camera
              ? ImageSource.camera
              : ImageSource.gallery,
          imageQuality: 90,
        );
        if (picked == null) return;
        final shrunk = await prepareAvatarPhoto(
          await picked.readAsBytes(),
          name: picked.name,
          nativeImplementations: room.client.nativeImplementations,
        );
        await setRoomAvatar(room, shrunk);
      }
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.commonPhotoUpdated)),
        );
      }
    } catch (e, s) {
      if (!isPickerAccessDenied(e)) reportCaught('update room photo', e, s);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.commonPhotoNotSaved)),
        );
      }
    } finally {
      if (mounted) setState(() => _savingAvatar = false);
    }
  }

  Future<void> _changeAccess() async {
    final room = widget.room;
    final l10n = context.l10n;
    final current = roomAccessOf(room);
    final communities = _community ? const <Room>[] : communitiesOf(room);
    final inCommunity = !_community && room.spaceParents.isNotEmpty;
    final choices = [
      if (!inCommunity) RoomAccess.public,
      if (communities.isNotEmpty) RoomAccess.community,
      if (inCommunity) RoomAccess.askToJoin,
      RoomAccess.private,
    ];
    final chosen = await showSheet<RoomAccess>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            for (final access in choices)
              ListTile(
                leading: access == current
                    ? const Icon(Icons.check_outlined)
                    : const SizedBox(width: 24),
                title: Text(access.label(l10n)),
                subtitle: Text(access.description(l10n)),
                onTap: () => Navigator.of(context).pop(access),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || chosen == current || !mounted) return;

    final confirmed = await _confirmAccessChange(chosen);
    if (!confirmed || !mounted) return;

    await _save(
      setSaving: (saving) => _savingAccess = saving,
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

  Future<bool> _confirmAccessChange(RoomAccess chosen) async {
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final l10n = context.l10n;
    final canEditName = room.canChangeStateEvent(EventTypes.RoomName);
    final canEditTopic = room.canChangeStateEvent(EventTypes.RoomTopic);
    final canEditAvatar =
        !room.isDirectChat && room.canChangeStateEvent(EventTypes.RoomAvatar);
    final canEditAlias = room.canChangeStateEvent(
      EventTypes.RoomCanonicalAlias,
    );
    final canEditHistoryVisibility = room.canChangeHistoryVisibility;
    final canEditAccess = canChangeRoomAccess(room);
    final aliasLocalpart = room.canonicalAlias.localpart;

    Widget trailingFor(bool saving, bool editable) {
      if (saving) {
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      }
      return editable
          ? const Icon(Icons.chevron_right_outlined)
          : const SizedBox.shrink();
    }

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
              if (!room.isDirectChat)
                ListTile(
                  leading: MxcAvatar(
                    client: room.client,
                    avatarUrl: room.avatar,
                    fallbackText: roomTitle(room, l10n),
                    toneSeed: roomToneSeed(room),
                    radius: 20,
                    shape: AvatarShape.forRoom(room),
                  ),
                  title: Text(
                    _community
                        ? l10n.roomInfoCommunityPhoto
                        : l10n.roomInfoRoomPhoto,
                  ),
                  trailing: trailingFor(_savingAvatar, canEditAvatar),
                  onTap: (_savingAvatar || !canEditAvatar)
                      ? null
                      : _changeAvatar,
                ),
              ListTile(
                leading: const Icon(Icons.title_outlined),
                title: Text(_nameLabel(l10n)),
                subtitle: Text(
                  room.name.isEmpty ? l10n.roomInfoNotSet : room.name,
                ),
                trailing: trailingFor(_savingName, canEditName),
                onTap: (_savingName || !canEditName) ? null : _editName,
              ),
              ListTile(
                leading: const Icon(Icons.notes_outlined),
                title: Text(_topicLabel(l10n)),
                subtitle: Text(
                  room.topic.isEmpty ? l10n.roomInfoNotSet : room.topic,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: trailingFor(_savingTopic, canEditTopic),
                onTap: (_savingTopic || !canEditTopic) ? null : _editTopic,
              ),
              if (!_community)
                ListTile(
                  leading: const Icon(Icons.tag_outlined),
                  title: Text(l10n.roomInfoMainAddress),
                  subtitle: Text(
                    aliasLocalpart == null
                        ? l10n.roomInfoNotSet
                        : '#$aliasLocalpart',
                  ),
                  trailing: trailingFor(_savingAlias, canEditAlias),
                  onTap: (_savingAlias || !canEditAlias) ? null : _editAlias,
                ),
            ],
          ),
          CardGroup(
            title: l10n.roomInfoPrivacy,
            children: [
              if (!_community)
                ListTile(
                  leading: const Icon(Icons.history_outlined),
                  title: Text(l10n.roomInfoWhoCanReadHistory),
                  subtitle: Text(
                    _historyVisibilityLabel(l10n, _historyVisibilityOf(room)),
                  ),
                  trailing: trailingFor(
                    _savingHistoryVisibility,
                    canEditHistoryVisibility,
                  ),
                  onTap: (_savingHistoryVisibility || !canEditHistoryVisibility)
                      ? null
                      : _changeHistoryVisibility,
                ),
              if (!room.isDirectChat)
                ListTile(
                  leading: const Icon(Icons.public_outlined),
                  title: Text(
                    _community
                        ? l10n.roomInfoCommunityAccess
                        : l10n.roomInfoRoomAccess,
                  ),
                  subtitle: Text(roomAccessOf(room).label(l10n)),
                  trailing: trailingFor(_savingAccess, canEditAccess),
                  onTap: (_savingAccess || !canEditAccess)
                      ? null
                      : _changeAccess,
                ),
            ],
          ),
        ],
      ),
    );
  }
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

class _EditTextFieldDialog extends StatefulWidget {
  final String title;
  final String initialValue;
  final String labelText;
  final String? prefixText;
  final int maxLines;
  final int? maxLength;
  final String? Function(String value)? validator;

  const _EditTextFieldDialog({
    required this.title,
    required this.initialValue,
    required this.labelText,
    this.prefixText,
    this.maxLines = 1,
    this.maxLength,
    this.validator,
  });

  @override
  State<_EditTextFieldDialog> createState() => _EditTextFieldDialogState();
}

class _EditTextFieldDialogState extends State<_EditTextFieldDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    final error = widget.validator?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: ZunoTextField(
        autofillHints: null,
        controller: _controller,
        autofocus: true,
        maxLines: widget.maxLines,
        maxLength: widget.maxLength,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          labelText: widget.labelText,
          prefixText: widget.prefixText,
          errorText: _error,
        ),
        onSubmitted: widget.maxLines == 1 ? (_) => _submit() : null,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(context.l10n.commonSave)),
      ],
    );
  }
}
