import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/active_call_provider.dart';
import '../../../core/calls/matrixrtc/call_unread_correction_provider.dart';
import '../../../core/calls/matrixrtc/call_waiting.dart';
import '../../../core/calls/matrixrtc/incoming_call.dart';
import '../../../core/calls/matrixrtc/incoming_call_provider.dart';
import '../../../core/calls/matrixrtc/resolved_call_ids_provider.dart';
import '../../../core/calls/notifications/call_notification_router.dart';
import '../../../core/calls/notifications/headless_call_decline_provider.dart';
import '../../../core/calls/notifications/pending_call_notification_action_provider.dart';
import '../../../core/calls/notifications/ring_notification.dart';
import '../../../core/calls/notifications/ringing_call_provider.dart';
import '../../../core/errors/best_effort.dart';
import '../../../core/errors/global_error_handler.dart';
import '../../../core/matrix/force_sync.dart';
import '../../../core/matrix/local_room_dialog.dart';
import '../../../core/matrix/local_username_dialog.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/room_access.dart';
import '../../../core/matrix/room_name_check.dart';
import '../../../core/matrix/room_exit.dart';
import '../../../core/notifications/delivery_auto_fallback.dart';
import '../../../core/notifications/encrypted_reaction_push_rule.dart';
import '../../../core/notifications/invite_notification_provider.dart';
import '../../../core/notifications/message_notification_provider.dart';
import '../../../core/onboarding/onboarding_provider.dart';
import '../../../core/onboarding/onboarding_step.dart';
import '../../../core/security/new_device_alert_provider.dart';
import '../../../core/security/security_prompt.dart';
import '../../../core/security/security_prompt_provider.dart';
import '../../../core/security/unverified_device_warning_provider.dart';
import '../../calls/presentation/incoming_call_page.dart';
import '../../chat/presentation/room_page.dart';
import '../../onboarding/presentation/onboarding_flow_page.dart';
import '../../settings/presentation/secure_backup_page.dart';
import '../../settings/presentation/settings_page.dart';
import '../../verification/presentation/verification_page.dart';
import 'chat_list_view.dart';
import 'new_device_alert_banner.dart';
import 'notification_delivery_banner.dart';
import 'public_rooms_sheet.dart';

Stream<void> _coalesced(Iterable<Stream<void>> streams) {
  late final StreamController<void> controller;
  final subs = <StreamSubscription<void>>[];
  var pending = false;
  void schedule() {
    if (pending) return;
    pending = true;
    scheduleMicrotask(() {
      pending = false;
      if (!controller.isClosed) controller.add(null);
    });
  }

  controller = StreamController<void>.broadcast(
    onListen: () {
      for (final s in streams) {
        subs.add(s.listen((_) => schedule()));
      }
    },
    onCancel: () async {
      for (final sub in subs) {
        await sub.cancel();
      }
      subs.clear();
    },
  );
  return controller.stream;
}

enum _NewChatType { directMessage, group, findPublicRooms, joinRoom }

enum _RoomAction { markRead, mute, unmute, exit }

class RoomListPage extends ConsumerWidget {
  const RoomListPage({super.key});

  Future<void> _newChat(BuildContext context, Client client) async {
    final type = await showModalBottomSheet<_NewChatType>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('New chat'),
              onTap: () =>
                  Navigator.of(context).pop(_NewChatType.directMessage),
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('New room'),
              onTap: () => Navigator.of(context).pop(_NewChatType.group),
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Find public rooms'),
              onTap: () =>
                  Navigator.of(context).pop(_NewChatType.findPublicRooms),
            ),
            ListTile(
              enabled: false,
              leading: const Icon(Icons.tag_outlined),
              title: const Text('Join room'),
              onTap: () => Navigator.of(context).pop(_NewChatType.joinRoom),
            ),
          ],
        ),
      ),
    );
    if (type == null || !context.mounted) return;

    switch (type) {
      case _NewChatType.directMessage:
        await _startDirectMessage(context, client);
      case _NewChatType.group:
        await _createGroup(context, client);
      case _NewChatType.findPublicRooms:
        await _findPublicRoom(context, client);
      case _NewChatType.joinRoom:
        await _joinRoom(context, client);
    }
  }

  Future<void> _startDirectMessage(BuildContext context, Client client) async {
    final userId = await showLocalUsernameDialog(
      context,
      client: client,
      title: 'New chat',
      actionLabel: 'Start',
    );
    if (userId == null || !context.mounted) return;
    await _createAndOpen(
      context,
      client,
      () => client.startDirectChat(userId, enableEncryption: true),
    );
  }

  Future<void> _createGroup(BuildContext context, Client client) async {
    final newRoom = await showDialog<_NewRoom>(
      context: context,
      builder: (_) => const _NewRoomDialog(),
    );
    if (newRoom == null || newRoom.name.isEmpty || !context.mounted) return;
    await _createAndOpen(
      context,
      client,
      () => createGroupRoom(client, name: newRoom.name, access: newRoom.access),
    );
  }

  Future<void> _findPublicRoom(BuildContext context, Client client) async {
    final roomId = await showPublicRoomsSheet(context, client: client);
    if (roomId == null || !context.mounted) return;
    final alreadyJoined =
        client.getRoomById(roomId)?.membership == Membership.join;
    await _createAndOpen(
      context,
      client,
      () async => alreadyJoined ? roomId : client.joinRoom(roomId),
    );
  }

  Future<void> _joinRoom(BuildContext context, Client client) async {
    final roomId = await showLocalRoomDialog(context, client: client);
    if (roomId == null || !context.mounted) return;
    await _createAndOpen(context, client, () => client.joinRoom(roomId));
  }

  Future<void> _createAndOpen(
    BuildContext context,
    Client client,
    Future<String> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final roomId = await action();
      final room = client.getRoomById(roomId);
      if (room != null && context.mounted) {
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => RoomPage(room: room)));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _refresh(BuildContext context, Client client) async {
    try {
      await forceSyncNow(client);
    } catch (e) {
      logCaught('sync', e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not refresh. Check your connection.'),
          ),
        );
      }
    }
  }

  Future<void> _maybeStartOnboarding(
    BuildContext context,
    WidgetRef ref,
    List<OnboardingStep> steps,
  ) async {
    if (steps.isEmpty) return;
    final store = ref.read(onboardingStoreProvider);
    if (store.flowInProgress) return;
    final userId = ref.read(matrixClientProvider).userID;
    final pending = userId == null
        ? steps
        : steps.where((s) => !store.shown(userId).contains(s)).toList();
    if (pending.isEmpty) return;
    store.flowInProgress = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OnboardingFlowPage(steps: pending)),
      );
    } finally {
      store.flowInProgress = false;
    }
  }

  Future<void> _maybeOfferRecovery(BuildContext context, WidgetRef ref) async {
    final store = ref.read(securityPromptStoreProvider);
    if (store.promptInFlight) return;
    final lastPrompted = store.lastPrompted();
    if (lastPrompted != null &&
        DateTime.now().difference(lastPrompted) < securityPromptCooldown) {
      return;
    }
    final pendingSteps = await ref.read(onboardingStepsProvider.future);
    if (!context.mounted || store.promptInFlight) return;
    if (recoveryPromptDefersToOnboarding(
      flowInProgress: ref.read(onboardingStoreProvider).flowInProgress,
      pendingSteps: pendingSteps,
    )) {
      return;
    }
    store.promptInFlight = true;
    try {
      await _offerRecovery(context, ref, store);
    } finally {
      store.promptInFlight = false;
    }
  }

  Future<void> _offerRecovery(
    BuildContext context,
    WidgetRef ref,
    SecurityPromptStore store,
  ) async {
    await store.markPrompted();
    if (!context.mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keep your messages if you lose this device'),
        actionsOverflowDirection: VerticalDirection.up,
        actionsOverflowButtonSpacing: 4,
        content: const Text(
          'Right now they exist only on this device. A recovery code is twelve '
          'words that bring them back on a new one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Set up recovery'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SecureBackupPage()));
  }

  Future<void> _handleIncomingVerification(
    BuildContext context,
    KeyVerification keyVerification,
  ) async {
    final accept = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verification request'),
        content: Text(
          '${withoutServer(keyVerification.userId)} wants to verify with you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Decline'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    if (accept != true) {
      await keyVerification.rejectVerification();
      return;
    }
    await keyVerification.acceptVerification();
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerificationPage(keyVerification: keyVerification),
        ),
      );
    }
  }

  Future<void> _showRoomActions(BuildContext context, Room room) async {
    final isMuted = room.pushRuleState == PushRuleState.dontNotify;
    final hasUnread = room.notificationCount > 0;

    final action = await showModalBottomSheet<_RoomAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            if (hasUnread)
              ListTile(
                leading: const Icon(Icons.mark_chat_read_outlined),
                title: const Text('Mark as read'),
                onTap: () => Navigator.of(context).pop(_RoomAction.markRead),
              ),
            ListTile(
              leading: Icon(
                isMuted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
              ),
              title: Text(isMuted ? 'Unmute' : 'Mute'),
              onTap: () =>
                  Navigator.of(context)
                      .pop(isMuted ? _RoomAction.unmute : _RoomAction.mute),
            ),
            ListTile(
              leading: Icon(
                roomExitIcon(room),
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                roomExitLabel(room),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.of(context).pop(_RoomAction.exit),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (action) {
        case _RoomAction.markRead:
          final lastEventId = room.lastEvent?.eventId;
          await room.setReadMarker(lastEventId, mRead: lastEventId);
        case _RoomAction.mute:
          await room.setPushRuleState(PushRuleState.dontNotify);
        case _RoomAction.unmute:
          await room.setPushRuleState(PushRuleState.notify);
        case _RoomAction.exit:
          await confirmAndExitRoom(context, room);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(matrixClientProvider);
    final unreadCorrections = ref.watch(callUnreadCorrectionProvider);
    ref.watch(resolvedCallIdsProvider);
    ref.watch(pendingCallNotificationActionProvider);
    ref.watch(messageNotificationProvider);
    ref.watch(roomInviteNotificationProvider);
    ref.watch(pushRuleMaintenanceProvider);
    ref.watch(deliveryAutoFallbackProvider);
    ref.watch(newDeviceAlertProvider);
    ref.watch(unvouchedDeviceWarningProvider);
    ref.watch(headlessCallDeclineProvider);
    ref.watch(callNotificationRouterProvider);
    ref.listen<AsyncValue<List<OnboardingStep>>>(onboardingStepsProvider, (
      _,
      next,
    ) {
      final steps = next.value;
      if (steps != null) _maybeStartOnboarding(context, ref, steps);
    });
    ref.listen<AsyncValue<SecurityPromptDecision>>(securityPromptProvider, (
      _,
      next,
    ) {
      if (next.value == SecurityPromptDecision.setUpRecovery) {
        _maybeOfferRecovery(context, ref);
      }
    });
    ref.listen<AsyncValue<KeyVerification>>(incomingKeyVerificationProvider, (
      _,
      next,
    ) {
      final keyVerification = next.value;
      if (keyVerification != null) {
        _handleIncomingVerification(context, keyVerification);
      }
    });
    ref.listen<AsyncValue<IncomingCall>>(incomingCallProvider, (_, next) {
      final call = next.value;
      if (call == null ||
          RingingCall.instance.callId == call.callId ||
          ref.read(resolvedCallIdsProvider).contains(call.callId)) {
        return;
      }

      if (ref.read(activeCallProvider) != null) {
        unawaited(autoDeclineIncomingCall(call));
        ref.read(resolvedCallIdsProvider.notifier).markResolved(call.callId);
        final callerName = call.room
            .unsafeGetUserFromMemoryOrFallback(call.callerId)
            .calcDisplayname();
        globalScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Missed call from $callerName')),
        );
        return;
      }

      unawaited(postRingNotification(call));
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => IncomingCallPage(call: call)));
    });

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        centerTitle: false,
        titleSpacing: 20,
        title: Text('Chats', style: Theme.of(context).textTheme.headlineMedium),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _newChat(context, client),
        tooltip: 'New chat',
        child: const Icon(Icons.add_outlined),
      ),
      body: Column(
        children: [
          const NewDeviceAlertBanner(),
          const NotificationDeliveryBanner(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _refresh(context, client),
              child: StreamBuilder<void>(
                stream: _coalesced([
                  client.onSync.stream,
                  client.onRoomState.stream,
                ]),
                builder: (context, _) => ChatListView(
                  client: client,
                  rooms: client.rooms,
                  unreadCorrections: unreadCorrections,
                  onOpen: (room) => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => RoomPage(room: room)),
                  ),
                  onActions: (room) => _showRoomActions(context, room),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

typedef _NewRoom = ({String name, RoomAccess access});

class _NewRoomDialog extends StatefulWidget {
  const _NewRoomDialog();

  @override
  State<_NewRoomDialog> createState() => _NewRoomDialogState();
}

class _NewRoomDialogState extends State<_NewRoomDialog> {
  final _controller = TextEditingController();
  RoomAccess _access = RoomAccess.private;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    final error = roomNameError(name);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop<_NewRoom>((name: name, access: _access));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('New room'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            autofillHints: null,
            controller: _controller,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'Room name',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<RoomAccess>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: RoomAccess.private,
                icon: Icon(Icons.public_off),
                label: Text('Private'),
              ),
              ButtonSegment(
                value: RoomAccess.public,
                icon: Icon(Icons.public),
                label: Text('Public'),
              ),
            ],
            selected: {_access},
            onSelectionChanged: (selection) =>
                setState(() => _access = selection.single),
          ),
          const SizedBox(height: 8),
          Text(
            _access.description,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}
