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
import '../../../core/calls/matrixrtc/ring_elsewhere_provider.dart';
import '../../../core/calls/notifications/call_notification_router.dart';
import '../../../core/calls/notifications/headless_call_decline_provider.dart';
import '../../../core/calls/notifications/pending_call_notification_action_provider.dart';
import '../../../core/calls/notifications/ring_notification.dart';
import '../../../core/calls/notifications/ringing_call_provider.dart';
import '../../../core/calls/platform/incoming_call_presenter.dart';
import '../../../core/calls/platform/system_ring.dart';
import '../../../core/errors/best_effort.dart';
import '../../../core/errors/connection_error.dart';
import '../../../core/errors/global_error_handler.dart';
import '../../../core/matrix/communities.dart';
import '../../../core/matrix/force_sync.dart';
import '../../../core/matrix/join_requests.dart';
import '../../../core/matrix/join_room.dart';
import '../../../core/matrix/local_username_dialog.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/room_access.dart';
import '../../../core/matrix/room_exit.dart';
import '../../../core/notifications/delivery_auto_fallback.dart';
import '../../../core/notifications/invite_notification_provider.dart';
import '../../../core/notifications/join_request_notification_provider.dart';
import '../../../core/notifications/message_notification_provider.dart';
import '../../../core/notifications/server_push_rules.dart';
import '../../../core/onboarding/onboarding_provider.dart';
import '../../../core/onboarding/onboarding_step.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/security/new_device_alert_provider.dart';
import '../../../core/security/security_prompt.dart';
import '../../../core/security/security_prompt_provider.dart';
import '../../../core/security/unverified_device_warning_provider.dart';
import '../../calls/presentation/incoming_call_page.dart';
import '../../communities/presentation/community_page.dart';
import '../../onboarding/presentation/onboarding_flow_page.dart';
import '../../settings/presentation/secure_backup_page.dart';
import '../../settings/presentation/settings_page.dart';
import '../../verification/presentation/verification_page.dart';
import 'chat_list_view.dart';
import 'home_bottom_bar.dart';
import 'new_device_alert_banner.dart';
import 'new_room_dialog.dart';
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

enum _NewChatType {
  directMessage,
  group,
  findPublicRooms,
  community,
  findPublicCommunities,
}

enum _RoomAction { markRead, mute, unmute, exit }

const _chatsMenu = [
  (_NewChatType.directMessage, Icons.person_outline, 'New chat'),
  (_NewChatType.group, Icons.groups_outlined, 'New room'),
  (_NewChatType.findPublicRooms, Icons.search, 'Find public rooms'),
];

const _communitiesMenu = [
  (_NewChatType.community, Icons.workspaces_outlined, 'New community'),
  (_NewChatType.findPublicCommunities, Icons.search, 'Find public communities'),
];

class RoomListPage extends ConsumerStatefulWidget {
  const RoomListPage({super.key});

  @override
  ConsumerState<RoomListPage> createState() => _RoomListPageState();
}

class _RoomListPageState extends ConsumerState<RoomListPage> {
  HomeTab _tab = HomeTab.chats;

  late final Stream<void> _updates = _coalesced([
    ref.read(matrixClientProvider).onSync.stream,
    ref.read(matrixClientProvider).onRoomState.stream,
  ]);

  void _select(HomeTab tab) {
    if (tab != _tab) setState(() => _tab = tab);
  }

  Future<void> _newChat(BuildContext context, Client client) async {
    final options = _tab == HomeTab.chats ? _chatsMenu : _communitiesMenu;
    final type = await showModalBottomSheet<_NewChatType>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            for (final (type, icon, label) in options)
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                onTap: () => Navigator.of(context).pop(type),
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
        await _findPublic(context, client, communities: false);
      case _NewChatType.community:
        await _createCommunity(context, client);
      case _NewChatType.findPublicCommunities:
        await _findPublic(context, client, communities: true);
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
      failed: 'Could not start the chat.',
    );
  }

  Future<void> _createGroup(BuildContext context, Client client) async {
    final newRoom = await showNewRoomDialog(context);
    if (newRoom == null || newRoom.name.isEmpty || !context.mounted) return;
    await _createAndOpen(
      context,
      client,
      () => createGroupRoom(client, name: newRoom.name, access: newRoom.access),
      failed: 'Could not create the room.',
    );
  }

  Future<void> _createCommunity(BuildContext context, Client client) async {
    final newCommunity = await showNewRoomDialog(
      context,
      title: 'New community',
      hint: 'Community name',
    );
    if (newCommunity == null || newCommunity.name.isEmpty || !context.mounted) {
      return;
    }
    await _createAndOpen(
      context,
      client,
      () => createCommunity(
        client,
        name: newCommunity.name,
        access: newCommunity.access,
      ),
      failed: 'Could not create the community.',
    );
  }

  Future<void> _findPublic(
    BuildContext context,
    Client client, {
    required bool communities,
  }) async {
    final roomId = await showPublicRoomsSheet(
      context,
      client: client,
      communities: communities,
    );
    if (roomId == null || !context.mounted) return;
    final alreadyJoined =
        client.getRoomById(roomId)?.membership == Membership.join;
    await _createAndOpen(
      context,
      client,
      () async {
        if (!alreadyJoined) await joinAndAwaitRoom(client, roomId);
        return roomId;
      },
      failed: communities
          ? 'Could not join the community.'
          : 'Could not join the room.',
    );
  }

  Future<void> _createAndOpen(
    BuildContext context,
    Client client,
    Future<String> Function() action, {
    required String failed,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final roomId = await action();
      final room = client.getRoomById(roomId);
      if (room != null && context.mounted) {
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => pageForRoom(room)));
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(e, failed: failed))),
      );
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
    final isCommunity = room.isSpace;
    final isMuted = room.pushRuleState == PushRuleState.dontNotify;
    final hasUnread = !isCommunity && room.notificationCount > 0;

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
            if (!isCommunity)
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
    Future<void> attempt(
      Future<void> Function() write, {
      required String failed,
    }) async {
      try {
        await write();
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(failureMessage(e, failed: failed))),
        );
      }
    }

    switch (action) {
      case _RoomAction.markRead:
        final lastEventId = room.lastEvent?.eventId;
        await attempt(
          () => room.setReadMarker(lastEventId, mRead: lastEventId),
          failed: 'Not marked as read.',
        );
      case _RoomAction.mute:
        await attempt(
          () => room.setPushRuleState(PushRuleState.dontNotify),
          failed: 'Not muted.',
        );
      case _RoomAction.unmute:
        await attempt(
          () => room.setPushRuleState(PushRuleState.notify),
          failed: 'Not unmuted.',
        );
      case _RoomAction.exit:
        await confirmAndExitRoom(context, room);
    }
  }

  bool _systemRingBusy(String callId) {
    final ringing = SystemRing.instance.ringing.value;
    return ringing != null && ringing.callId != callId;
  }

  Future<void> _ringThroughSystem(
    IncomingCall call,
    IncomingCallPresenter presenter,
  ) async {
    var outcome = RingOutcome.unavailable;
    try {
      outcome = await postRingNotification(call, presenter: presenter);
    } finally {
      if (outcome != RingOutcome.shown) SystemRing.instance.clear(call.callId);
    }
    if (outcome != RingOutcome.unavailable || !mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => IncomingCallPage(call: call)));
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(matrixClientProvider);
    final unreadCorrections = ref.watch(callUnreadCorrectionProvider);
    ref.watch(resolvedCallIdsProvider);
    ref.watch(ringElsewhereProvider);
    ref.watch(pendingCallNotificationActionProvider);
    ref.watch(messageNotificationProvider);
    ref.watch(roomInviteNotificationProvider);
    ref.watch(joinRequestNotificationProvider);
    final pendingJoins = ref.watch(joinRequestsProvider);
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

      if (answeredOnAnotherDevice(call.room, call.callId)) {
        ref.read(resolvedCallIdsProvider.notifier).markResolved(call.callId);
        unawaited(
          ref
              .read(incomingCallPresenterProvider)
              .cancelIncoming(
                roomId: call.room.id,
                callId: call.callId,
                end: RingEnd.answeredElsewhere,
              ),
        );
        return;
      }

      if (ref.read(activeCallProvider) != null ||
          _systemRingBusy(call.callId)) {
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

      SystemRing.instance.set(roomId: call.room.id, callId: call.callId);
      final presenter = ref.read(incomingCallPresenterProvider);
      if (ref.read(platformCapabilitiesProvider).callKit) {
        unawaited(_ringThroughSystem(call, presenter));
        return;
      }
      unawaited(postRingNotification(call, presenter: presenter));
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => IncomingCallPage(call: call)));
    });

    final communities = _tab == HomeTab.communities;
    void open(Room room) =>
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => pageForRoom(room)));

    return PopScope(
      canPop: !communities,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(HomeTab.chats);
      },
      child: StreamBuilder<void>(
        stream: _updates,
        builder: (context, _) {
          final layout = arrangeHome(client.rooms, pendingJoins: pendingJoins);
          return Scaffold(
            appBar: AppBar(
              toolbarHeight: 72,
              centerTitle: false,
              titleSpacing: 20,
              title: Text(
                communities ? 'Communities' : 'Chats',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            bottomNavigationBar: HomeBottomBar(
              selected: _tab,
              chatsUnread: layout.hasUnreadChats(unreadCorrections),
              communitiesUnread: layout.hasUnreadCommunities(unreadCorrections),
              onSelect: _select,
              onNew: () => _newChat(context, client),
            ),
            body: Column(
              children: [
                const NewDeviceAlertBanner(),
                const NotificationDeliveryBanner(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _refresh(context, client),
                    child: communities
                        ? ChatListView.communities(
                            key: const ValueKey(HomeTab.communities),
                            client: client,
                            layout: layout,
                            unreadCorrections: unreadCorrections,
                            onOpen: open,
                            onActions: (room) =>
                                _showRoomActions(context, room),
                          )
                        : ChatListView.chats(
                            key: const ValueKey(HomeTab.chats),
                            client: client,
                            layout: layout,
                            unreadCorrections: unreadCorrections,
                            onOpen: open,
                            onActions: (room) =>
                                _showRoomActions(context, room),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
