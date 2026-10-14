import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/end_call.dart';
import '../../../core/calls/incoming_call_gate.dart';
import '../../../core/calls/matrixrtc/call_unread_correction_provider.dart';
import '../../../core/calls/matrixrtc/incoming_call.dart';
import '../../../core/calls/matrixrtc/incoming_call_provider.dart';
import '../../../core/calls/matrixrtc/resolved_call_ids_provider.dart';
import '../../../core/calls/matrixrtc/ring_elsewhere_provider.dart';
import '../../../core/calls/notifications/call_notification_router.dart';
import '../../../core/calls/notifications/headless_call_decline_provider.dart';
import '../../../core/calls/notifications/headless_message_action_provider.dart';
import '../../../core/calls/notifications/pending_call_notification_action_provider.dart';
import '../../../core/calls/notifications/ring_notification.dart';
import '../../../core/calls/platform/incoming_call_presenter.dart';
import '../../../core/calls/platform/system_ring.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/errors/connection_error.dart';
import '../../../core/l10n/display_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/communities.dart';
import '../../../core/matrix/join_requests.dart';
import '../../../core/matrix/join_room.dart';
import '../../../core/matrix/local_username_dialog.dart';
import '../../../core/matrix/matrix_client_provider.dart';
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
import '../../../core/security/verification_cancel_message.dart';
import '../../../core/ui/sheet.dart';
import '../../../core/ui/zuno_motion.dart';
import '../../calls/presentation/incoming_call_page.dart';
import '../../communities/presentation/community_page.dart';
import '../../location/presentation/own_live_location_banner.dart';
import '../../onboarding/presentation/onboarding_flow_page.dart';
import '../../settings/presentation/secure_backup_page.dart';
import '../../settings/presentation/settings_page.dart';
import '../../verification/presentation/verification_page.dart';
import '../../verification/presentation/verification_request_dialog.dart';
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

List<(_NewChatType, IconData, String)> _chatsMenu(AppLocalizations l10n) => [
  (_NewChatType.directMessage, Icons.person_outline, l10n.roomsNewChat),
  (_NewChatType.group, Icons.groups_outlined, l10n.roomsNewRoom),
  (_NewChatType.findPublicRooms, Icons.search, l10n.roomsFindPublicRooms),
];

List<(_NewChatType, IconData, String)> _communitiesMenu(
  AppLocalizations l10n,
) => [
  (_NewChatType.community, Icons.workspaces_outlined, l10n.roomsNewCommunity),
  (
    _NewChatType.findPublicCommunities,
    Icons.search,
    l10n.roomsFindPublicCommunities,
  ),
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
    final l10n = context.l10n;
    final options = _tab == HomeTab.chats
        ? _chatsMenu(l10n)
        : _communitiesMenu(l10n);
    final type = await showSheet<_NewChatType>(
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
      title: context.l10n.roomsNewChat,
      actionLabel: context.l10n.roomsStart,
    );
    if (userId == null || !context.mounted) return;
    await _createAndOpen(
      context,
      client,
      () => client.startDirectChat(userId, enableEncryption: true),
      failed: context.l10n.roomsCouldNotStartChat,
    );
  }

  Future<void> _createGroup(BuildContext context, Client client) async {
    final newRoom = await showNewRoomDialog(context);
    if (newRoom == null || newRoom.name.isEmpty || !context.mounted) return;
    await _createAndOpen(
      context,
      client,
      () => createGroupRoom(client, name: newRoom.name, access: newRoom.access),
      failed: context.l10n.roomsCouldNotCreateRoom,
    );
  }

  Future<void> _createCommunity(BuildContext context, Client client) async {
    final newCommunity = await showNewRoomDialog(
      context,
      title: context.l10n.roomsNewCommunity,
      hint: context.l10n.communitiesCommunityName,
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
      failed: context.l10n.roomsCouldNotCreateCommunity,
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
          ? context.l10n.roomsCouldNotJoinCommunity
          : context.l10n.roomsCouldNotJoinRoom,
    );
  }

  Future<void> _createAndOpen(
    BuildContext context,
    Client client,
    Future<String> Function() action, {
    @displayText required String failed,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      final roomId = await action();
      final room = client.getRoomById(roomId);
      if (room != null && context.mounted) {
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => pageForRoom(room)));
      }
    } on RoomListingRefused {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.matrixRoomListingRefused)),
      );
    } catch (e, s) {
      reportCaught('create or join room', e, s);
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(l10n, e, failed: failed))),
      );
    }
  }

  Future<void> _maybeStartOnboarding(
    BuildContext context,
    WidgetRef ref,
    List<OnboardingStep> steps,
  ) async {
    final store = ref.read(onboardingStoreProvider);
    if (store.flow != OnboardingFlow.undecided) return;
    if (steps.isEmpty) {
      store.flow = OnboardingFlow.done;
      return;
    }
    store.flow = OnboardingFlow.open;
    try {
      await Navigator.of(context).push(
        ForwardExitPageRoute(builder: (_) => OnboardingFlowPage(steps: steps)),
      );
    } finally {
      store.flow = OnboardingFlow.done;
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
      flow: ref.read(onboardingStoreProvider).flow,
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
        title: Text(context.l10n.roomsRecoveryPromptTitle),
        actionsOverflowDirection: VerticalDirection.up,
        actionsOverflowButtonSpacing: 4,
        content: Text(context.l10n.roomsRecoveryPromptBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonNotNow),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.securitySetUpRecovery),
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
    if (keyVerification.isDone) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final isOwnDevice =
        keyVerification.userId == ref.read(matrixClientProvider).userID;
    final accept = await showDialog<bool>(
      context: context,
      builder: (_) =>
          VerificationRequestDialog(keyVerification: keyVerification),
    );
    if (keyVerification.isDone) {
      final message = verificationCancelMessage(
        l10n,
        code: keyVerification.canceledCode,
        isOwnDevice: isOwnDevice,
      );
      messenger.showSnackBar(SnackBar(content: Text(message.body)));
      return;
    }
    if (accept != true) {
      await keyVerification.rejectVerification();
      return;
    }
    await keyVerification.acceptVerification();
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerificationPage(
            keyVerification: keyVerification,
            isOwnDevice: isOwnDevice,
          ),
        ),
      );
    }
  }

  Future<void> _showRoomActions(BuildContext context, Room room) async {
    final isCommunity = room.isSpace;
    final isMuted = room.pushRuleState == PushRuleState.dontNotify;
    final hasUnread = !isCommunity && room.notificationCount > 0;

    final action = await showSheet<_RoomAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            if (hasUnread)
              ListTile(
                leading: const Icon(Icons.mark_chat_read_outlined),
                title: Text(context.l10n.commonMarkAsRead),
                onTap: () => Navigator.of(context).pop(_RoomAction.markRead),
              ),
            if (!isCommunity)
              ListTile(
                leading: Icon(
                  isMuted
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                ),
                title: Text(
                  isMuted ? context.l10n.roomsUnmute : context.l10n.roomsMute,
                ),
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
                roomExitLabel(room, context.l10n),
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
    final l10n = context.l10n;
    Future<void> attempt(
      Future<void> Function() write, {
      @displayText required String failed,
    }) async {
      try {
        await write();
      } catch (e, s) {
        reportCaught('room action ${action.name}', e, s);
        messenger.showSnackBar(
          SnackBar(content: Text(failureMessage(l10n, e, failed: failed))),
        );
      }
    }

    switch (action) {
      case _RoomAction.markRead:
        final lastEventId = room.lastEvent?.eventId;
        await attempt(
          () => room.setReadMarker(lastEventId, mRead: lastEventId),
          failed: l10n.roomsNotMarkedAsRead,
        );
      case _RoomAction.mute:
        await attempt(
          () => room.setPushRuleState(PushRuleState.dontNotify),
          failed: l10n.roomsNotMuted,
        );
      case _RoomAction.unmute:
        await attempt(
          () => room.setPushRuleState(PushRuleState.notify),
          failed: l10n.roomsNotUnmuted,
        );
      case _RoomAction.exit:
        await confirmAndExitRoom(
          context,
          room,
          endCallsIn: ref.read(endCallsInProvider),
        );
    }
  }

  Future<void> _onIncomingCall(IncomingCall call) async {
    final gate = ref.read(incomingCallGateProvider.notifier);
    if (!await gate.shouldRing(call) || !mounted) return;
    SystemRing.instance.set(roomId: call.room.id, callId: call.callId);
    unawaited(
      postRingNotification(
        call,
        presenter: ref.read(incomingCallPresenterProvider),
      ),
    );
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
    final firstSyncPending = ref.watch(firstSyncProvider).isLoading;
    ref.watch(pushRuleMaintenanceProvider);
    ref.watch(deliveryAutoFallbackProvider);
    ref.watch(newDeviceAlertProvider);
    ref.watch(unvouchedDeviceWarningProvider);
    ref.watch(headlessCallDeclineProvider);
    ref.watch(headlessMessageActionProvider);
    ref.watch(callNotificationRouterProvider);
    ref.listen<AsyncValue<List<OnboardingStep>>>(onboardingStepsProvider, (
      _,
      next,
    ) {
      final steps = next.value;
      if (steps != null && !next.isLoading) {
        _maybeStartOnboarding(context, ref, steps);
      }
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
      if (ref.read(platformCapabilitiesProvider).voipRing) return;
      final call = next.value;
      if (call != null) unawaited(_onIncomingCall(call));
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
          final loading = firstSyncPending && client.rooms.isEmpty;
          return Scaffold(
            appBar: AppBar(
              toolbarHeight: 72,
              centerTitle: false,
              titleSpacing: 20,
              title: Text(
                _tab.label(context.l10n),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: context.l10n.roomsSettings,
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
                OwnLiveLocationBanner(onOpen: open),
                Expanded(
                  child: communities
                      ? ChatListView.communities(
                          key: const ValueKey(HomeTab.communities),
                          client: client,
                          layout: layout,
                          unreadCorrections: unreadCorrections,
                          onOpen: open,
                          onActions: (room) => _showRoomActions(context, room),
                          loading: loading,
                        )
                      : ChatListView.chats(
                          key: const ValueKey(HomeTab.chats),
                          client: client,
                          layout: layout,
                          unreadCorrections: unreadCorrections,
                          onOpen: open,
                          onActions: (room) => _showRoomActions(context, room),
                          loading: loading,
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
