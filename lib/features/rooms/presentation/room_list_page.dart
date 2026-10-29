import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/end_call.dart';
import '../../../core/calls/matrixrtc/call_unread_correction_provider.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/display_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/communities.dart';
import '../../../core/matrix/join_requests.dart';
import '../../../core/matrix/join_room.dart';
import '../../../core/matrix/local_username_dialog.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/read_receipts.dart';
import '../../../core/matrix/room_access.dart';
import '../../../core/matrix/room_changes.dart';
import '../../../core/matrix/room_exit.dart';
import '../../../core/matrix/room_mute.dart';
import '../../../core/onboarding/onboarding_provider.dart';
import '../../../core/onboarding/onboarding_step.dart';
import '../../../core/security/security_prompt.dart';
import '../../../core/security/security_prompt_provider.dart';
import '../../../core/ui/confirm_dialog.dart';
import '../../../core/ui/notice.dart';
import '../../../core/ui/sheet.dart';
import '../../../core/ui/zuno_motion.dart';
import '../../communities/presentation/community_page.dart';
import '../../location/presentation/own_live_location_banner.dart';
import '../../onboarding/presentation/onboarding_flow_page.dart';
import '../../security_alerts/presentation/security_alert_banners.dart';
import '../../settings/presentation/secure_backup_page.dart';
import '../../settings/presentation/settings_page.dart';
import 'chat_list_view.dart';
import 'home_bottom_bar.dart';
import 'new_room_dialog.dart';
import 'notification_delivery_banner.dart';
import 'public_rooms_sheet.dart';

enum _NewChatType {
  directMessage,
  group,
  findPublicRooms,
  community,
  findPublicCommunities,
}

enum _RoomAction { markRead, mute, unmute, exit }

List<SheetAction<_NewChatType>> _newChatActions(
  HomeTab tab,
  AppLocalizations l10n,
) => switch (tab) {
  HomeTab.chats => [
    SheetAction(
      _NewChatType.directMessage,
      icon: Icons.person_outline,
      label: l10n.roomsNewChat,
    ),
    SheetAction(
      _NewChatType.group,
      icon: Icons.groups_outlined,
      label: l10n.roomsNewRoom,
    ),
    SheetAction(
      _NewChatType.findPublicRooms,
      icon: Icons.search,
      label: l10n.roomsFindPublicRooms,
    ),
  ],
  HomeTab.communities => [
    SheetAction(
      _NewChatType.community,
      icon: Icons.workspaces_outlined,
      label: l10n.roomsNewCommunity,
    ),
    SheetAction(
      _NewChatType.findPublicCommunities,
      icon: Icons.search,
      label: l10n.roomsFindPublicCommunities,
    ),
  ],
};

class RoomListPage extends ConsumerStatefulWidget {
  const RoomListPage({super.key});

  @override
  ConsumerState<RoomListPage> createState() => _RoomListPageState();
}

class _RoomListPageState extends ConsumerState<RoomListPage> {
  HomeTab _tab = HomeTab.chats;

  Client get _client => ref.read(matrixClientProvider);

  void _select(HomeTab tab) {
    if (tab != _tab) setState(() => _tab = tab);
  }

  void _open(Room room) =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => pageForRoom(room)));

  Future<void> _newChat() async {
    final type = await showActionSheet(
      context,
      actions: _newChatActions(_tab, context.l10n),
    );
    if (type == null || !mounted) return;

    switch (type) {
      case _NewChatType.directMessage:
        await _startDirectMessage();
      case _NewChatType.group:
        await _createGroup();
      case _NewChatType.findPublicRooms:
        await _findPublic(communities: false);
      case _NewChatType.community:
        await _createCommunity();
      case _NewChatType.findPublicCommunities:
        await _findPublic(communities: true);
    }
  }

  Future<void> _startDirectMessage() async {
    final client = _client;
    final userId = await showLocalUsernameDialog(
      context,
      client: client,
      title: context.l10n.roomsNewChat,
      actionLabel: context.l10n.roomsStart,
    );
    if (userId == null || !mounted) return;
    await _createAndOpen(
      () => startEncryptedDirectChat(client, userId),
      failed: context.l10n.roomsCouldNotStartChat,
    );
  }

  Future<void> _createGroup() async {
    final newRoom = await showNewRoomDialog(context);
    if (newRoom == null || newRoom.name.isEmpty || !mounted) return;
    await _createAndOpen(
      () =>
          createGroupRoom(_client, name: newRoom.name, access: newRoom.access),
      failed: context.l10n.roomsCouldNotCreateRoom,
    );
  }

  Future<void> _createCommunity() async {
    final newCommunity = await showNewRoomDialog(
      context,
      title: context.l10n.roomsNewCommunity,
      hint: context.l10n.communitiesCommunityName,
    );
    if (newCommunity == null || newCommunity.name.isEmpty || !mounted) return;
    await _createAndOpen(
      () => createCommunity(
        _client,
        name: newCommunity.name,
        access: newCommunity.access,
      ),
      failed: context.l10n.roomsCouldNotCreateCommunity,
    );
  }

  Future<void> _findPublic({required bool communities}) async {
    final client = _client;
    final roomId = await showPublicRoomsSheet(
      context,
      client: client,
      communities: communities,
    );
    if (roomId == null || !mounted) return;
    final alreadyJoined =
        client.getRoomById(roomId)?.membership == Membership.join;
    await _createAndOpen(
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
    Future<String> Function() action, {
    @displayText required String failed,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      final room = _client.getRoomById(await action());
      if (room != null && mounted) _open(room);
    } on RoomListingRefused {
      messenger.say(l10n.matrixRoomListingRefused);
    } catch (e, s) {
      reportCaught('create or join room', e, s);
      messenger.sayFailed(l10n, e, failed: failed);
    }
  }

  Future<void> _maybeStartOnboarding(List<OnboardingStep> steps) async {
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

  Future<void> _maybeOfferRecovery() async {
    final store = ref.read(securityPromptStoreProvider);
    if (store.promptInFlight) return;
    final lastPrompted = store.lastPrompted();
    if (lastPrompted != null &&
        clock.now().difference(lastPrompted) < securityPromptCooldown) {
      return;
    }
    final pendingSteps = await ref.read(onboardingStepsProvider.future);
    if (!mounted || store.promptInFlight) return;
    if (recoveryPromptDefersToOnboarding(
      flow: ref.read(onboardingStoreProvider).flow,
      pendingSteps: pendingSteps,
    )) {
      return;
    }
    store.promptInFlight = true;
    try {
      await _offerRecovery(store);
    } finally {
      store.promptInFlight = false;
    }
  }

  Future<void> _offerRecovery(SecurityPromptStore store) async {
    await store.markPrompted();
    if (!mounted) return;
    final l10n = context.l10n;
    final accepted = await confirm(
      context,
      title: l10n.roomsRecoveryPromptTitle,
      body: l10n.roomsRecoveryPromptBody,
      confirmLabel: l10n.securitySetUpRecovery,
      cancelLabel: l10n.commonNotNow,
      tone: ConfirmTone.primary,
    );
    if (!accepted || !mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SecureBackupPage()));
  }

  Future<void> _showRoomActions(Room room) async {
    final l10n = context.l10n;
    final isCommunity = room.isSpace;
    final isMuted = isRoomMuted(room);
    final hasUnread = !isCommunity && room.notificationCount > 0;

    final action = await showActionSheet(
      context,
      actions: [
        if (hasUnread)
          SheetAction(
            _RoomAction.markRead,
            icon: Icons.mark_chat_read_outlined,
            label: l10n.commonMarkAsRead,
          ),
        if (!isCommunity)
          isMuted
              ? SheetAction(
                  _RoomAction.unmute,
                  icon: Icons.notifications_active_outlined,
                  label: l10n.roomsUnmute,
                )
              : SheetAction(
                  _RoomAction.mute,
                  icon: Icons.notifications_off_outlined,
                  label: l10n.roomsMute,
                ),
        SheetAction(
          _RoomAction.exit,
          icon: roomExitIcon(room),
          label: roomExitLabel(room, l10n),
          destructive: true,
        ),
      ],
    );
    if (action == null || !mounted) return;

    switch (action) {
      case _RoomAction.markRead:
        await attempt(
          context,
          () async {
            final eventId = await newestReadMarkerEventId(room);
            if (eventId == null) return;
            await markRoomRead(room, eventId);
          },
          label: 'room action mark read',
          failed: l10n.roomsNotMarkedAsRead,
        );
      case _RoomAction.mute || _RoomAction.unmute:
        await _setMuted(room, action == _RoomAction.mute);
      case _RoomAction.exit:
        await confirmAndExitRoom(
          context,
          room,
          endCallsIn: ref.read(endCallsInProvider),
        );
    }
  }

  Future<void> _setMuted(Room room, bool muted) async {
    final asked = askToMuteRoom(context, room, muted);
    setState(() {});
    await asked;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(matrixClientProvider);
    final unreadCorrections = ref.watch(callUnreadCorrectionProvider);
    final pendingJoins = ref.watch(joinRequestsProvider);
    final firstSyncPending = ref.watch(firstSyncProvider).isLoading;
    ref.listen<AsyncValue<List<OnboardingStep>>>(onboardingStepsProvider, (
      _,
      next,
    ) {
      final steps = next.value;
      if (steps != null && !next.isLoading) _maybeStartOnboarding(steps);
    });
    ref.listen<AsyncValue<SecurityPromptDecision>>(securityPromptProvider, (
      _,
      next,
    ) {
      if (next.value == SecurityPromptDecision.setUpRecovery) {
        _maybeOfferRecovery();
      }
    });

    final communities = _tab == HomeTab.communities;
    return PopScope(
      canPop: !communities,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(HomeTab.chats);
      },
      child: RoomChangesBuilder(
        changes: RoomChanges.everywhere(client),
        builder: (context) {
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
              onNew: _newChat,
            ),
            body: Column(
              children: [
                const SecurityAlertBanners.account(),
                const NotificationDeliveryBanner(),
                OwnLiveLocationBanner(onOpen: _open),
                Expanded(
                  child: ChatListView(
                    key: ValueKey(_tab),
                    client: client,
                    layout: layout,
                    section: _tab,
                    unreadCorrections: unreadCorrections,
                    onOpen: _open,
                    onActions: _showRoomActions,
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
