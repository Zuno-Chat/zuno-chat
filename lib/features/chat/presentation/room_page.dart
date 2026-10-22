import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/active_call_provider.dart';
import '../../../core/calls/matrixrtc/active_room_call.dart';
import '../../../core/calls/matrixrtc/call_member_state.dart';
import '../../../core/calls/matrixrtc/call_unread_correction_provider.dart';
import '../../../core/calls/models/call_kind.dart';
import '../../../core/errors/best_effort.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/display_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/connectivity_provider.dart';
import '../../../core/matrix/currently_open_room_provider.dart';
import '../../../core/matrix/read_receipts.dart';
import '../../../core/matrix/room_invite.dart';
import '../../../core/matrix/room_permission.dart';
import '../../../core/matrix/room_state_rebuild.dart';
import '../../../core/matrix/room_timeline_reload.dart';
import '../../../core/matrix/sync_coordinator_provider.dart';
import '../../../core/matrix/voice_recording.dart';
import '../../../core/navigation/chat_route.dart';
import '../../../core/notifications/messages/message_notifications.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/security/recovery_code.dart';
import '../../../core/security/recovery_code_leak.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/share/inbound_share.dart';
import '../../../core/ui/keep_clear.dart';
import '../../../core/ui/route_settled.dart';
import '../../calls/presentation/active_call_banner.dart';
import '../../calls/presentation/room_calls.dart';
import '../../communities/presentation/join_requests_view.dart';
import '../../location/presentation/live_location_banner.dart';
import '../../room_info/presentation/room_info_page.dart';
import '../../security_alerts/presentation/security_alert_banners.dart';
import '../data/discarded_sends.dart';
import '../data/message_kinds.dart';
import '../data/room_sender.dart';
import '../data/sync_filter.dart';
import '../data/typing_announcer.dart';
import 'attachment_menu.dart';
import 'chat_wallpaper.dart';
import 'mention_suggestions.dart';
import 'message_actions.dart';
import 'message_composer.dart';
import 'message_list_view.dart';
import 'pending_invite_banner.dart';
import 'recovery_code_warning.dart';
import 'reply_target_cache.dart';
import 'room_app_bar.dart';
import 'room_lifecycle.dart';
import 'room_menu.dart';
import 'voice_recorder.dart';

const _doubleTapReaction = '❤️';
const _scrollToBottomThreshold = 300.0;

class RoomPage extends ConsumerStatefulWidget {
  final Room room;
  final InboundShare? pendingShare;

  const RoomPage({required this.room, this.pendingShare, super.key});

  @override
  ConsumerState<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends ConsumerState<RoomPage>
    with
        WidgetsBindingObserver,
        RouteSettled<RoomPage>,
        RoomStateRebuild<RoomPage> {
  final _input = TextEditingController();
  final _scrollController = ScrollController();
  final _showScrollToBottom = ValueNotifier(false);
  late final TypingAnnouncer _typing;
  late final VoiceRecorder _recorder;
  Timeline? _timeline;
  Timeline? _pendingTimeline;
  Event? _editingEvent;
  String _draftBeforeEdit = '';
  Event? _replyingToEvent;

  StreamSubscription<SyncUpdate>? _syncSub;
  String? _lastMarkedReadEventId;
  bool _historyStalled = false;

  late var _replyTargets = _newReplyTargets();
  bool _activeCallBannerShown = false;
  bool _gettingFile = false;

  late final CurrentlyOpenRoomIdNotifier _currentlyOpenRoomNotifier;

  bool _isForeground = true;

  RoomSender get _sender => ref.read(roomSenderProvider(widget.room));

  @override
  Client get roomStateClient => widget.room.client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentlyOpenRoomNotifier = ref.read(currentlyOpenRoomIdProvider.notifier);
    _typing = TypingAnnouncer(
      room: widget.room,
      input: _input,
      enabled: () => ref.read(sendTypingIndicatorProvider),
    );
    _recorder = VoiceRecorder(
      setup: voiceRecordingSetup(ref.read(platformCapabilitiesProvider)),
      onRecorded: (clip) => _sender.sendVoice(
        clip.bytes,
        duration: clip.duration,
        waveform: clip.waveform,
      ),
      onProblem: _onRecordingProblem,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _currentlyOpenRoomNotifier.set(widget.room.id);
      final share = widget.pendingShare;
      if (share != null) _applyPendingShare(share);
    });
    unawaited(
      MessageNotifications.instance.cancelMessageNotification(widget.room.id),
    );
    _scrollController.addListener(_maybeLoadMoreHistory);
    _scrollController.addListener(_updateScrollToBottomVisibility);
    unawaited(_loadTimeline());
    _syncSub = widget.room.client.onSync.stream.listen((update) {
      if (!mounted) return;
      if (_historyStalled) _resumeHistory();
      if (_activeCallBannerShown || syncTouchesRoom(update, widget.room.id)) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    markChatRoute(context, widget.room.id);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = isRoomForeground(state);
    if (isForeground == _isForeground) return;
    _isForeground = isForeground;
    if (isForeground) {
      _currentlyOpenRoomNotifier.set(widget.room.id);
      unawaited(
        MessageNotifications.instance.cancelMessageNotification(widget.room.id),
      );
      _markLatestRead();
    } else {
      if (_currentlyOpenRoomNotifier.current == widget.room.id) {
        _currentlyOpenRoomNotifier.set(null);
      }
    }
  }

  ReplyTargetCache _newReplyTargets() => ReplyTargetCache(
    widget.room.getEventById,
    keysArrived: widget.room.onSessionKeyReceived.stream,
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_maybeLoadMoreHistory);
    _scrollController.removeListener(_updateScrollToBottomVisibility);
    _scrollController.dispose();
    _showScrollToBottom.dispose();
    _replyTargets.dispose();
    _timeline?.cancelSubscriptions();
    _pendingTimeline?.cancelSubscriptions();
    _syncSub?.cancel();
    _typing.dispose();
    _input.dispose();
    _recorder.dispose();
    final notifier = _currentlyOpenRoomNotifier;
    final roomId = widget.room.id;
    scheduleMicrotask(() {
      if (notifier.current == roomId) notifier.set(null);
    });
    super.dispose();
  }

  Future<void> _openRoomInfo() async {
    final navigator = Navigator.of(context);
    final result = await navigator.push<RoomInfoResult>(
      MaterialPageRoute(
        builder: (_) => RoomInfoPage(
          room: widget.room,
          onStartCall: (kind) {
            navigator.pop();
            unawaited(_startCall(kind));
          },
        ),
      ),
    );
    if (result == RoomInfoResult.left && mounted) navigator.pop();
  }

  Future<void> _startCall(CallKind kind) =>
      startRoomCall(context, ref, widget.room, kind);

  void _applyPendingShare(InboundShare share) {
    if (!mounted) return;
    final text = share.text;
    if (text != null) _showInComposer(text);
    unawaited(sendSharedFiles(context, ref, widget.room, share.files));
  }

  void _showAttachmentMenu() => unawaited(
    showAttachmentMenu(
      context,
      ref,
      widget.room,
      onFetchingFile: (fetching) {
        if (mounted) setState(() => _gettingFile = fetching);
      },
    ),
  );

  @override
  void onRouteSettled() {
    setState(() {});
    _applyPendingTimeline();
  }

  void _applyPendingTimeline() {
    final timeline = _pendingTimeline;
    if (timeline == null) return;
    _pendingTimeline = null;
    setState(() => _timeline = timeline);
    _markLatestRead();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeLoadMoreHistory(),
    );
  }

  Future<void> _loadTimeline() async {
    final timeline = await widget.room.getTimeline(
      onUpdate: () {
        if (!mounted || _timeline == null) return;
        setState(() {});
        _markLatestRead();
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _maybeLoadMoreHistory(),
        );
      },
    );
    if (!mounted) {
      timeline.cancelSubscriptions();
      return;
    }
    _pendingTimeline = timeline;
    unawaited(
      ref.read(discardedSendsProvider).settle(widget.room, timeline.events),
    );
    if (routeSettled) _applyPendingTimeline();
  }

  Future<void> _reloadMessages() async {
    _timeline?.cancelSubscriptions();
    _replyTargets.dispose();
    setState(() {
      _timeline = null;
      _replyTargets = _newReplyTargets();
      _historyStalled = false;
    });
    try {
      await reloadRoomTimeline(
        widget.room,
        sync: ref.read(syncCoordinatorProvider),
      );
    } catch (e, s) {
      reportCaught('reload messages', e, s);
      if (mounted) _snack(context.l10n.chatMessagesNotReloaded);
    }
    await _loadTimeline();
  }

  void _snack(@displayText String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _onRecordingProblem(VoiceRecordingProblem problem) {
    if (!mounted) return;
    final l10n = context.l10n;
    _snack(switch (problem) {
      VoiceRecordingProblem.microphoneDenied => l10n.chatMicrophoneAccessNeeded,
      VoiceRecordingProblem.didNotStart => l10n.chatRecordingDidNotStart,
      VoiceRecordingProblem.notSent => l10n.chatVoiceMessageNotSent,
    });
  }

  void _markLatestRead() {
    if (!_isForeground) return;
    final timeline = _timeline;
    if (timeline == null) return;
    final latest = timeline.events.where(canCarryReadMarker).firstOrNull;
    if (latest == null || latest.eventId == _lastMarkedReadEventId) return;
    final eventId = latest.eventId;
    _lastMarkedReadEventId = eventId;
    unawaited(
      runBestEffort(
        () => markRoomRead(widget.room, eventId),
        label: 'setReadMarker',
      ).then((ok) {
        if (!ok && _lastMarkedReadEventId == eventId) {
          _lastMarkedReadEventId = null;
        }
      }),
    );
    ref.read(callUnreadCorrectionProvider.notifier).clearFor(widget.room.id);
  }

  void _maybeLoadMoreHistory() {
    if (!mounted || _historyStalled) return;
    final timeline = _timeline;
    if (timeline == null || !timeline.canRequestHistory) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 400) return;
    if (ref.read(isOfflineProvider).value ?? false) return;
    unawaited(_requestHistory(timeline));
  }

  Future<void> _requestHistory(Timeline timeline) async {
    final ok = await runBestEffort(
      timeline.requestHistory,
      label: 'requestHistory',
    );
    if (!ok) _historyStalled = true;
  }

  void _resumeHistory() {
    _historyStalled = false;
    _maybeLoadMoreHistory();
  }

  void _retryAfterReconnect() {
    _markLatestRead();
    _resumeHistory();
    _sender.retryAll(_timeline);
  }

  void _updateScrollToBottomVisibility() {
    if (!_scrollController.hasClients) return;
    _showScrollToBottom.value =
        _scrollController.position.pixels > _scrollToBottomThreshold;
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    unawaited(
      _confirmThenSend(
        text,
        editing: _editingEvent,
        replyingTo: _replyingToEvent,
      ),
    );
  }

  Future<void> _confirmThenSend(
    String text, {
    Event? editing,
    Event? replyingTo,
  }) async {
    final wordlist = await _recoveryWordlist();
    if (!mounted) return;
    if (messageRevealsRecoveryCode(text, wordlist)) {
      final send = await confirmSendingRecoveryCode(context);
      if (!send || !mounted) return;
    }
    setState(() {
      if (_editingEvent == null) _input.clear();
      _leaveEdit();
      _replyingToEvent = null;
    });
    await _sender.sendText(text, editing: editing, replyingTo: replyingTo);
  }

  Future<RecoveryWordlist?> _recoveryWordlist() async {
    try {
      return await ref.read(recoveryWordlistProvider.future);
    } catch (_) {
      return null;
    }
  }

  void _showInComposer(String text) {
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
  }

  void _leaveEdit() {
    if (_editingEvent == null) return;
    _editingEvent = null;
    _showInComposer(_draftBeforeEdit);
    _draftBeforeEdit = '';
  }

  void _startReply(Event event) {
    setState(() {
      _leaveEdit();
      _replyingToEvent = event;
    });
  }

  void _startEdit(Event event) {
    setState(() {
      if (_editingEvent == null) _draftBeforeEdit = _input.text;
      _replyingToEvent = null;
      _editingEvent = event;
      _showInComposer(displayBody(event, _timeline!));
    });
  }

  void _cancelCompose() {
    setState(() {
      _leaveEdit();
      _replyingToEvent = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showHiddenMessages = ref.watch(showHiddenMessagesProvider);
    final sender = ref.watch(roomSenderProvider(widget.room));
    ref.listen<AsyncValue<bool>>(isOfflineProvider, (previous, next) {
      if (becameOnline(previous, next)) _retryAfterReconnect();
    });
    final timeline = _timeline;
    final ownUserId = widget.room.client.userID;
    final canCall =
        canPublishCallMemberState(widget.room) && hasSomeoneToCall(widget.room);
    final activeRoomCall = ownUserId == null
        ? null
        : findActiveRoomCall(widget.room, excludeUserId: ownUserId);
    final showActiveCallBanner =
        canCall &&
        activeRoomCall != null &&
        ref.watch(activeCallProvider)?.callId != activeRoomCall.callId;
    _activeCallBannerShown = showActiveCallBanner;

    final l10n = context.l10n;
    final inviteDisplay = roomInviteDisplay(widget.room, l10n);
    final canPost = canPostInRoom(widget.room);

    return Scaffold(
      appBar: RoomAppBar(
        room: widget.room,
        canCall: canCall,
        onOpenInfo: _openRoomInfo,
        onStartCall: _startCall,
        menuBuilder: (_) => roomMenuItems(
          context,
          ref,
          widget.room,
          onOpenInfo: _openRoomInfo,
          onReload: () => unawaited(_reloadMessages()),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            const ChatWallpaperBackground(),
            Positioned.fill(
              child: Column(
                children: [
                  SecurityAlertBanners.room(widget.room),
                  PendingInviteBanner(room: widget.room),
                  JoinRequestsBanner(room: widget.room),
                  if (showActiveCallBanner)
                    ActiveCallBanner(
                      call: activeRoomCall,
                      onJoin: () => joinRoomCall(
                        context,
                        ref,
                        widget.room,
                        activeRoomCall,
                      ),
                    ),
                  LiveLocationBanner(room: widget.room),
                  Expanded(
                    child: timeline == null
                        ? _TimelinePlaceholder(loading: routeSettled)
                        : Stack(
                            children: [
                              ListenableBuilder(
                                listenable: sender,
                                builder: (_, _) => MessageListView(
                                  room: widget.room,
                                  timeline: timeline,
                                  controller: _scrollController,
                                  showHiddenMessages: showHiddenMessages,
                                  canRespond: canPost,
                                  failedSends: sender.failed,
                                  pendingSend: sender.pending,
                                  replyTargets: _replyTargets,
                                  onLongPress: (event, gallery) =>
                                      showMessageActions(
                                        context,
                                        ref,
                                        room: widget.room,
                                        timeline: timeline,
                                        event: event,
                                        gallery: gallery,
                                        onReply: _startReply,
                                        onEdit: _startEdit,
                                      ),
                                  onDoubleTap: (event) => reactToMessage(
                                    context,
                                    event,
                                    timeline,
                                    _doubleTapReaction,
                                  ),
                                  onSwipeReply: _startReply,
                                  onResend: sender.resend,
                                  onRetryFailedSend: sender.retry,
                                ),
                              ),
                              Positioned(
                                right: 12,
                                bottom: 12,
                                child: _ScrollToLatestButton(
                                  visible: _showScrollToBottom,
                                  onPressed: _scrollToBottom,
                                ),
                              ),
                            ],
                          ),
                  ),
                  KeepClearArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (timeline != null &&
                            (_editingEvent != null || _replyingToEvent != null))
                          ComposeBar(
                            title: _editingEvent != null
                                ? l10n.chatEditingMessage
                                : l10n.chatReplyingTo(
                                    _replyingToEvent!.senderFromMemoryOrFallback
                                        .calcDisplayname(),
                                  ),
                            snippet: previewSnippet(
                              l10n,
                              _editingEvent ?? _replyingToEvent!,
                              timeline,
                            ),
                            onCancel: _cancelCompose,
                          ),
                        if (!widget.room.isDirectChat && canPost)
                          MentionSuggestions(
                            room: widget.room,
                            controller: _input,
                          ),
                        if (canPost)
                          MessageComposer(
                            controller: _input,
                            onSend: _send,
                            onAttach: _showAttachmentMenu,
                            attaching: _gettingFile,
                            recorder: _recorder,
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Center(
                              child: Text(
                                widget.room.isAbandonedDMRoom
                                    ? l10n.chatPartnerLeft(inviteDisplay.title)
                                    : l10n.chatCannotSend,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelinePlaceholder extends StatelessWidget {
  final bool loading;

  const _TimelinePlaceholder({required this.loading});

  @override
  Widget build(BuildContext context) {
    if (!loading) return const SizedBox.expand();
    return const Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _ScrollToLatestButton extends StatelessWidget {
  final ValueListenable<bool> visible;
  final VoidCallback onPressed;

  const _ScrollToLatestButton({required this.visible, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: visible,
      builder: (context, show, _) {
        if (!show) return const SizedBox.shrink();
        return Tooltip(
          message: context.l10n.chatScrollToLatest,
          child: Material(
            color: colors.surfaceContainerHighest,
            shape: CircleBorder(side: BorderSide(color: colors.outlineVariant)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  Icons.keyboard_arrow_down,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
