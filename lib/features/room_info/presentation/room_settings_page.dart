import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/optimistic_room_state.dart';
import '../../../core/matrix/room_access.dart';
import '../../../core/matrix/room_avatar.dart';
import '../../../core/matrix/room_name_check.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';

const _avatarMaxDimension = 512;

enum _AvatarAction { camera, gallery, remove }

String _historyVisibilityLabel(HistoryVisibility? visibility) =>
    switch (visibility) {
      HistoryVisibility.worldReadable => 'Anyone',
      HistoryVisibility.shared =>
        'Members, including history before they joined',
      HistoryVisibility.invited => 'Members, from when they were invited',
      HistoryVisibility.joined => 'Members, from when they joined',
      null => 'Unknown',
    };

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
  bool _savingName = false;
  bool _savingTopic = false;
  bool _savingAvatar = false;
  bool _savingAlias = false;
  bool _savingHistoryVisibility = false;
  bool _savingAccess = false;

  Future<void> _editName() async {
    final room = widget.room;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _EditTextFieldDialog(
        title: 'Room name',
        initialValue: room.name,
        labelText: 'Room name',
        maxLength: roomNameMaxLength,
        validator: roomNameError,
      ),
    );
    if (name == null || name.isEmpty || name == room.name || !mounted) return;

    await _save(
      setSaving: (saving) => _savingName = saving,
      success: 'Room name updated',
      failure: 'Room name not saved',
      write: () async {
        await room.setName(name);
        applyOptimisticRoomState(room, EventTypes.RoomName, {'name': name});
      },
    );
  }

  Future<void> _save({
    required void Function(bool saving) setSaving,
    required String success,
    required String failure,
    required Future<void> Function() write,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => setSaving(true));
    try {
      await write();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (e) {
      logCaught(failure, e);
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('$failure. Try again.')));
      }
    } finally {
      if (mounted) setState(() => setSaving(false));
    }
  }

  Future<void> _editTopic() async {
    final room = widget.room;
    final topic = await showDialog<String>(
      context: context,
      builder: (_) => _EditTextFieldDialog(
        title: 'Topic',
        initialValue: room.topic,
        labelText: 'Topic',
        maxLines: 3,
        maxLength: roomTopicMaxLength,
      ),
    );
    if (topic == null || topic == room.topic || !mounted) return;

    await _save(
      setSaving: (saving) => _savingTopic = saving,
      success: 'Topic updated',
      failure: 'Topic not saved',
      write: () async {
        await room.setDescription(topic);
        applyOptimisticRoomState(room, EventTypes.RoomTopic, {'topic': topic});
      },
    );
  }

  Future<void> _editAlias() async {
    final room = widget.room;
    final domain = room.client.userID!.domain;
    final current = room.canonicalAlias.localpart ?? '';
    final localpart = await showDialog<String>(
      context: context,
      builder: (_) => _EditTextFieldDialog(
        title: 'Main address',
        initialValue: current,
        labelText: 'Main address',
        prefixText: '#',
        maxLength: roomAliasMaxLength,
      ),
    );
    if (localpart == null || localpart == current || !mounted) return;

    await _save(
      setSaving: (saving) => _savingAlias = saving,
      success: 'Main address updated',
      failure: 'Main address not saved',
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
    final current = room.historyVisibility;
    final chosen = await showModalBottomSheet<HistoryVisibility>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            for (final visibility in HistoryVisibility.values)
              ListTile(
                leading: visibility == current
                    ? const Icon(Icons.check_outlined)
                    : const SizedBox(width: 24),
                title: Text(_historyVisibilityLabel(visibility)),
                onTap: () => Navigator.of(context).pop(visibility),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || chosen == current || !mounted) return;

    await _save(
      setSaving: (saving) => _savingHistoryVisibility = saving,
      success: 'History setting updated',
      failure: 'History setting not saved',
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
    final action = await showModalBottomSheet<_AvatarAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.of(context).pop(_AvatarAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(context).pop(_AvatarAction.gallery),
            ),
            if (room.avatar != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
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
        final shrunk = await MatrixImageFile.shrink(
          bytes: await picked.readAsBytes(),
          name: picked.name,
          maxDimension: _avatarMaxDimension,
          nativeImplementations: room.client.nativeImplementations,
        );
        await setRoomAvatar(room, shrunk);
      }
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('Photo updated')));
      }
    } catch (e) {
      logCaught('update room photo', e);
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Photo not saved. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingAvatar = false);
    }
  }

  Future<void> _changeAccess() async {
    final room = widget.room;
    final current = roomAccessOf(room);
    final chosen = await showModalBottomSheet<RoomAccess>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            for (final access in RoomAccess.values)
              ListTile(
                leading: access == current
                    ? const Icon(Icons.check_outlined)
                    : const SizedBox(width: 24),
                title: Text(access.label),
                subtitle: Text(access.description),
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
      success: 'Room access updated',
      failure: 'Room access not saved',
      write: () => setRoomAccess(room, chosen),
    );
  }

  Future<bool> _confirmAccessChange(RoomAccess chosen) async {
    final makingPublic = chosen == RoomAccess.public;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(makingPublic ? 'Make room public?' : 'Make room private?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in _accessConsequences(chosen))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('• $line'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(makingPublic ? 'Make public' : 'Make private'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
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
      appBar: AppBar(title: const Text('Room settings')),
      body: CardListView(
        children: [
          CardGroup(
            title: 'Room info',
            children: [
              if (!room.isDirectChat)
                ListTile(
                  leading: MxcAvatar(
                    client: room.client,
                    avatarUrl: room.avatar,
                    fallbackText: roomTitle(room),
                    radius: 20,
                  ),
                  title: const Text('Room photo'),
                  trailing: trailingFor(_savingAvatar, canEditAvatar),
                  onTap: (_savingAvatar || !canEditAvatar)
                      ? null
                      : _changeAvatar,
                ),
              ListTile(
                leading: const Icon(Icons.title_outlined),
                title: const Text('Room name'),
                subtitle: Text(room.name.isEmpty ? 'Not set' : room.name),
                trailing: trailingFor(_savingName, canEditName),
                onTap: (_savingName || !canEditName) ? null : _editName,
              ),
              ListTile(
                leading: const Icon(Icons.notes_outlined),
                title: const Text('Topic'),
                subtitle: Text(
                  room.topic.isEmpty ? 'Not set' : room.topic,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: trailingFor(_savingTopic, canEditTopic),
                onTap: (_savingTopic || !canEditTopic) ? null : _editTopic,
              ),
              ListTile(
                leading: const Icon(Icons.tag_outlined),
                title: const Text('Main address'),
                subtitle: Text(
                  aliasLocalpart == null ? 'Not set' : '#$aliasLocalpart',
                ),
                trailing: trailingFor(_savingAlias, canEditAlias),
                onTap: (_savingAlias || !canEditAlias) ? null : _editAlias,
              ),
            ],
          ),
          CardGroup(
            title: 'Privacy',
            children: [
              ListTile(
                leading: const Icon(Icons.history_outlined),
                title: const Text('Who can read history'),
                subtitle: Text(_historyVisibilityLabel(room.historyVisibility)),
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
                  title: const Text('Room access'),
                  subtitle: Text(roomAccessOf(room).label),
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

List<String> _accessConsequences(RoomAccess access) => switch (access) {
  RoomAccess.public => const [
    'Anyone can find it under Find public rooms.',
    'Anyone can join without an invite.',
    'Whether new members can read older messages depends on '
        'Who can read history.',
  ],
  RoomAccess.private => const [
    'The room leaves the public list.',
    'New people need an invite to join.',
    'Current members stay. Nobody is removed.',
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
      content: TextField(
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
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
