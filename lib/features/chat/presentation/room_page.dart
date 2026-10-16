import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart' hide CallSession;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/calls/active_call_controller.dart';
import '../../../core/calls/active_call_provider.dart';
import '../../../core/calls/end_call.dart';
import '../../../core/calls/matrixrtc/active_room_call.dart';
import '../../../core/calls/matrixrtc/call_member_state.dart';
import '../../../core/calls/matrixrtc/call_session.dart';
import '../../../core/calls/matrixrtc/call_unread_correction_provider.dart';
import '../../../core/calls/models/call_kind.dart';
import '../../../core/errors/best_effort.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/files/picked_file.dart';
import '../../../core/format/date_labels.dart';
import '../../../core/l10n/display_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/location/live_location_availability.dart';
import '../../../core/location/live_location_sharing.dart';
import '../../../core/location/location_message.dart';
import '../../../core/matrix/abuse_report.dart';
import '../../../core/matrix/attachment_action_buttons.dart';
import '../../../core/matrix/bearer_authorization.dart';
import '../../../core/matrix/connectivity_provider.dart';
import '../../../core/matrix/currently_open_room_provider.dart';
import '../../../core/matrix/event_display.dart';
import '../../../core/matrix/image_send_preparation.dart';
import '../../../core/matrix/local_username_dialog.dart';
import '../../../core/matrix/looks_like_video.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/media_gallery_group.dart';
import '../../../core/matrix/media_processing_exception.dart';
import '../../../core/matrix/media_quality.dart';
import '../../../core/matrix/picker_access.dart';
import '../../../core/matrix/read_receipts.dart';
import '../../../core/matrix/room_exit.dart';
import '../../../core/matrix/room_invite.dart';
import '../../../core/matrix/room_permission.dart';
import '../../../core/matrix/room_timeline_reload.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/matrix/send_failure.dart';
import '../../../core/matrix/send_progress.dart';
import '../../../core/matrix/sync_coordinator_provider.dart';
import '../../../core/matrix/upload_foreground_service.dart';
import '../../../core/matrix/video_send_preparation.dart';
import '../../../core/matrix/voice_recording.dart';
import '../../../core/navigation/chat_route.dart';
import '../../../core/notifications/messages/message_notifications.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/security/recovery_code.dart';
import '../../../core/security/recovery_code_leak.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/share/inbound_share.dart';
import '../../../core/shortcuts/home_screen_shortcut.dart';
import '../../../core/ui/keep_clear.dart';
import '../../../core/ui/route_settled.dart';
import '../../../core/ui/sheet.dart';
import '../../calls/presentation/call_page.dart';
import '../../communities/presentation/join_requests_view.dart';
import '../../location/presentation/live_location_banner.dart';
import '../../location/presentation/live_location_text.dart';
import '../../location/presentation/location_share_sheet.dart';
import '../../reports/presentation/report_sheet.dart';
import '../../room_info/presentation/room_info_page.dart';
import '../data/discarded_sends.dart';
import '../data/message_kinds.dart';
import '../data/pending_attachment_send.dart';
import '../data/sync_filter.dart';
import 'chat_wallpaper.dart';
import 'identity_change_banner.dart';
import 'image_caption_composer_page.dart';
import 'media_caption_composer_page.dart';
import 'mention_suggestions.dart';
import 'message_actions_sheet.dart';
import 'message_composer.dart';
import 'message_contents/reactions_row.dart';
import 'message_contents/voice_message.dart';
import 'message_list_view.dart';
import 'not_sent.dart';
import 'pending_invite_banner.dart';
import 'recovery_code_warning.dart';
import 'reply_target_cache.dart';
import 'room_app_bar.dart';
import 'room_lifecycle.dart';
import 'sender_device_tile.dart';
import 'unvouched_device_banner.dart';
import 'video_caption_composer_page.dart';

const _doubleTapReaction = '❤️';

class RoomPage extends ConsumerStatefulWidget {
  final Room room;
  final InboundShare? pendingShare;

  const RoomPage({required this.room, this.pendingShare, super.key});

  @override
  ConsumerState<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends ConsumerState<RoomPage>
    with WidgetsBindingObserver, RouteSettled<RoomPage> {
  final _input = TextEditingController();
  final _scrollController = ScrollController();
  final _showScrollToBottom = ValueNotifier(false);
  Timeline? _timeline;
  Timeline? _pendingTimeline;
  Event? _editingEvent;
  String _draftBeforeEdit = '';
  Event? _replyingToEvent;

  StreamSubscription<SyncUpdate>? _syncSub;
  StreamSubscription<({String roomId, StrippedStateEvent state})>?
  _roomStateSub;
  bool _roomStateRebuildPending = false;
  String? _lastMarkedReadEventId;
  bool _historyStalled = false;

  final _pendingSend = ValueNotifier<PendingAttachmentSend?>(null);
  late var _replyTargets = _newReplyTargets();
  bool _activeCallBannerShown = false;

  final List<FailedMediaSend> _failedSends = [];
  final _copies = <String>{};
  final _copyUses = <String, int>{};

  final _recorder = AudioRecorder();
  bool _recording = false;
  bool _gettingFile = false;
  final _recordingDuration = ValueNotifier(Duration.zero);

  @visibleForTesting
  ValueNotifier<Duration> get recordingDuration => _recordingDuration;
  Timer? _recordingTicker;
  String? _recordingPath;
  DateTime? _recordingStartedAt;
  final List<double> _waveformSamples = [];
  StreamSubscription<Amplitude>? _amplitudeSub;
  double _recordingSlideOffset = 0;
  static const _micHoldThreshold = Duration(milliseconds: 150);
  Timer? _micHoldTimer;
  Offset? _micDownPosition;
  bool _micHeld = false;
  bool _tapToggleRecording = false;

  static const _typingTimeout = Duration(seconds: 20);
  static const _typingRefreshInterval = Duration(seconds: 10);
  static const _typingIdleTimeout = Duration(seconds: 5);
  bool _isTypingSent = false;
  Timer? _typingRefreshTimer;
  Timer? _typingIdleTimer;

  late final CurrentlyOpenRoomIdNotifier _currentlyOpenRoomNotifier;

  bool _isForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentlyOpenRoomNotifier = ref.read(currentlyOpenRoomIdProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _currentlyOpenRoomNotifier.set(widget.room.id);
      final share = widget.pendingShare;
      if (share != null) unawaited(_applyPendingShare(share));
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
    _roomStateSub = widget.room.client.onRoomState.stream.listen((_) {
      if (_roomStateRebuildPending || !mounted) return;
      _roomStateRebuildPending = true;
      scheduleMicrotask(() {
        _roomStateRebuildPending = false;
        if (mounted) setState(() {});
      });
    });
    _input.addListener(_onComposerChangedForTyping);
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
    _pendingSend.dispose();
    _recordingDuration.dispose();
    _showScrollToBottom.dispose();
    _replyTargets.dispose();
    _timeline?.cancelSubscriptions();
    _pendingTimeline?.cancelSubscriptions();
    _roomStateSub?.cancel();
    _syncSub?.cancel();
    _input.removeListener(_onComposerChangedForTyping);
    _input.dispose();
    _recordingTicker?.cancel();
    _amplitudeSub?.cancel();
    _micHoldTimer?.cancel();
    _recorder.dispose();
    _typingRefreshTimer?.cancel();
    _typingIdleTimer?.cancel();
    for (final path in _copies) {
      if (!_copyUses.containsKey(path)) unawaited(discardTemporaryCopy(path));
    }
    if (_isTypingSent) {
      unawaited(
        runBestEffort(
          () => widget.room.setTyping(false),
          label: 'setTyping false',
        ),
      );
    }
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
    unawaited(_settleDiscarded(timeline));
    if (routeSettled) _applyPendingTimeline();
  }

  Future<void> _settleDiscarded(Timeline timeline) async {
    final discarded = ref.read(discardedSendsProvider);
    final room = widget.room;
    final kept = <Event>[];
    for (final event in [...timeline.events]) {
      final (:txid, :galleryId) = sendIdentity(event);
      final dropped =
          !event.status.isSent &&
          event.senderId == room.client.userID &&
          discarded.contains(room, [txid, galleryId]) &&
          await runBestEffort(
            () => _discardUnsent(discarded, event),
            label: 'discard a deleted send',
          );
      if (!dropped) kept.add(event);
    }
    await discarded.prune(room, kept);
  }

  Future<void> _discardUnsent(DiscardedSends discarded, Event event) async {
    final txid = sendIdentity(event).txid;
    if (discarded.isSending(txid)) {
      await discarded.add(widget.room, txid);
      if (event.status.isError) await event.cancelSend();
    } else {
      await event.cancelSend();
      await discarded.remove(widget.room, txid);
    }
  }

  void _snack(@displayText String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addMembers() async {
    final room = widget.room;
    final l10n = context.l10n;
    final userId = await showLocalUsernameDialog(
      context,
      client: room.client,
      title: l10n.chatAddMembers,
      actionLabel: l10n.commonInvite,
    );
    if (userId == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await room.invite(userId);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonInvitationSent)),
      );
    } catch (e, s) {
      if (!isUnknownInvitee(e)) reportCaught('invite', e, s);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonInvitationNotSent)),
      );
    }
  }

  Future<Uint8List?> _fetchRoomAvatarBytes() async {
    final room = widget.room;
    final avatarUrl = room.avatar;
    if (avatarUrl == null) return null;
    try {
      final client = room.client;
      final uri = await avatarUrl.getThumbnailUri(
        client,
        width: 192,
        height: 192,
      );
      final response = await client.httpClient.get(
        uri,
        headers: {'authorization': await bearerAuthorization(client)},
      );
      return response.statusCode == 200 ? response.bodyBytes : null;
    } catch (e, s) {
      reportCaught('fetch shortcut icon', e, s);
      return null;
    }
  }

  Future<void> _addToHomeScreen() async {
    final room = widget.room;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final iconBytes = await _fetchRoomAvatarBytes();
    try {
      final requested = await pinRoomShortcut(
        roomId: room.id,
        label: roomTitle(room, l10n),
        iconBytes: iconBytes,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            requested
                ? l10n.chatShortcutRequested
                : l10n.chatShortcutUnsupported,
          ),
        ),
      );
    } catch (e, s) {
      reportCaught('add shortcut', e, s);
      messenger.showSnackBar(SnackBar(content: Text(l10n.chatShortcutFailed)));
    }
  }

  Future<void> _reinitializeConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.chatReloadTitle),
        content: Text(context.l10n.chatReloadBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.chatReload),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

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

  void _onComposerChangedForTyping() {
    if (!ref.read(sendTypingIndicatorProvider)) return;
    if (_input.text.trim().isNotEmpty) {
      _startTypingIndicator();
    } else {
      _stopTypingIndicator();
    }
  }

  void _startTypingIndicator() {
    _typingIdleTimer?.cancel();
    _typingIdleTimer = Timer(_typingIdleTimeout, _stopTypingIndicator);
    if (_isTypingSent) return;
    _isTypingSent = true;
    unawaited(
      runBestEffort(
        () =>
            widget.room.setTyping(true, timeout: _typingTimeout.inMilliseconds),
        label: 'setTyping true',
      ),
    );
    _typingRefreshTimer = Timer.periodic(_typingRefreshInterval, (_) {
      unawaited(
        runBestEffort(
          () => widget.room.setTyping(
            true,
            timeout: _typingTimeout.inMilliseconds,
          ),
          label: 'setTyping true',
        ),
      );
    });
  }

  void _stopTypingIndicator() {
    _typingIdleTimer?.cancel();
    _typingRefreshTimer?.cancel();
    if (!_isTypingSent) return;
    _isTypingSent = false;
    unawaited(
      runBestEffort(
        () => widget.room.setTyping(false),
        label: 'setTyping false',
      ),
    );
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
        () => widget.room.setReadMarker(eventId, mRead: eventId),
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

  static const _scrollToBottomThreshold = 300.0;

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
    await _sendText(text, editing: editing, replyingTo: replyingTo);
  }

  Future<RecoveryWordlist?> _recoveryWordlist() async {
    try {
      return await ref.read(recoveryWordlistProvider.future);
    } catch (_) {
      return null;
    }
  }

  Future<void> _sendText(
    String text, {
    Event? editing,
    Event? replyingTo,
  }) async {
    await runBestEffort(
      () => widget.room.sendTextEvent(
        text,
        editEventId: editing?.eventId,
        inReplyTo: replyingTo,
        parseMarkdown: false,
        parseCommands: false,
      ),
      label: 'send a text message',
    );
  }

  bool _busyWithCall() {
    final active = ref.read(activeCallProvider);
    if (active == null || active.phase == CallSessionPhase.ended) return false;
    final call = active.room.id == widget.room.id
        ? ref.read(activeCallControllerProvider)
        : null;
    if (call != null) {
      showCallScreen(Navigator.of(context), call);
    } else {
      _snack(context.l10n.chatAlreadyInCall);
    }
    return true;
  }

  Future<void> _startCall(CallKind kind) async {
    if (_busyWithCall()) return;
    if (!canPublishCallMemberState(widget.room)) {
      _snack(context.l10n.callsFailureNoPermission);
      return;
    }
    if (!hasSomeoneToCall(widget.room)) {
      _snack(context.l10n.chatNobodyJoined);
      return;
    }
    if (ref.read(isOfflineProvider).value ?? false) {
      _snack(context.l10n.chatNoConnection);
      return;
    }
    if (ref.read(confirmBeforeCallingProvider)) {
      final name = roomTitle(widget.room, context.l10n);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.chatCallTitle(name)),
          content: Text(
            kind == CallKind.video
                ? context.l10n.chatStartVideoCall
                : context.l10n.chatStartVoiceCall,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.callsStartCall),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    _openCall(
      () => CallSession.startOutgoing(
        widget.room,
        kind,
        lowDataMode: ref.read(lowDataCallsProvider),
      ),
    );
  }

  CallSession? _openCall(CallSession Function() create) {
    final session = ref.read(activeCallProvider.notifier).start(create);
    if (session == null) {
      _busyWithCall();
      return null;
    }
    final call = ref.read(activeCallControllerProvider);
    if (call != null) showCallScreen(Navigator.of(context), call);
    return session;
  }

  Future<void> _joinActiveCall(ActiveRoomCall call) async {
    if (_busyWithCall()) return;
    if (!canPublishCallMemberState(widget.room)) {
      _snack(context.l10n.chatNoJoinCallPermission);
      return;
    }
    if (ref.read(isOfflineProvider).value ?? false) {
      _snack(context.l10n.chatNoConnection);
      return;
    }
    final session = _openCall(
      () => CallSession.forIncoming(
        room: widget.room,
        callId: call.callId,
        kind: CallKind.values.asNameMap()[call.kind] ?? CallKind.voice,
        lowDataMode: ref.read(lowDataCallsProvider),
      ),
    );
    session?.accept().ignore();
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

  Future<void> _deleteMessages(
    List<Event> events, {
    bool gallery = false,
  }) async {
    final many = events.length > 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.chatDeleteTitle(events.length)),
        content: Text(switch (many) {
          true => context.l10n.chatDeleteManyBody,
          false when isNotSent(events.single) =>
            context.l10n.chatDeleteUnsentBody,
          false => context.l10n.chatDeleteOneBody,
        }),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              many ? context.l10n.chatDeleteAll : context.l10n.commonDelete,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final sharing = ref.read(liveLocationSharingProvider);
    final discarded = ref.read(discardedSendsProvider);
    if (gallery) await _stopGalleries(events, discarded);
    var failed = false;
    for (final event in events.map(_current)) {
      try {
        await sharing.stopShareStartedBy(event);
        if (event.status.isSent) {
          await widget.room.redactEvent(event.eventId);
        } else {
          await _discardUnsent(discarded, event);
        }
      } catch (e, s) {
        reportCaught('delete message', e, s);
        failed = true;
      }
    }
    if (!failed) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          many ? l10n.chatDeleteManyFailed : l10n.chatDeleteOneFailed,
        ),
      ),
    );
  }

  Future<void> _stopGalleries(
    List<Event> events,
    DiscardedSends discarded,
  ) async {
    final ids = {for (final event in events) ?sendIdentity(event).galleryId};
    for (final id in ids) {
      await discarded.add(widget.room, id);
    }
    final dropped = [
      for (final failed in _failedSends)
        if (ids.contains(failed.gallery?.id)) failed,
    ];
    if (dropped.isEmpty) return;
    setState(() => _failedSends.removeWhere(dropped.contains));
    unawaited(_releaseCopies([for (final failed in dropped) ?failed.path]));
  }

  Event _current(Event event) {
    final id = sendIdentity(event).txid;
    return _timeline?.events
            .where((e) => e.matchesEventOrTransactionId(id))
            .firstOrNull ??
        event;
  }

  Future<void> _showMessageActions(
    Event event, {
    List<Event>? galleryEvents,
  }) async {
    final timeline = _timeline;
    if (timeline == null || event.redacted) return;
    final isOwn = event.senderId == widget.room.client.userID;
    final sent = event.status.isSent;
    final canDelete =
        (isOwn || widget.room.canRedact) &&
        (sent || isNotSent(event) || galleryEvents != null);
    final displayEvent = event.getDisplayEvent(timeline);
    final canPost = canPostInRoom(widget.room);
    final canEdit =
        canPost &&
        sent &&
        isOwn &&
        !event.hasAttachment &&
        displayEvent.messageType == MessageTypes.Text;
    final attachmentKind = classifyAttachment(displayEvent);
    final isAttachment = switch (attachmentKind) {
      AttachmentKind.none ||
      AttachmentKind.location ||
      AttachmentKind.liveLocation => false,
      AttachmentKind.image ||
      AttachmentKind.video ||
      AttachmentKind.voice ||
      AttachmentKind.file => true,
    };
    final isTextMessage =
        !isAttachment && attachmentKind != AttachmentKind.liveLocation;
    final galleryCount = galleryEvents?.length ?? 0;
    final l10n = context.l10n;
    final labels = DateLabels.of(context);

    final action = await showMessageActionsSheet(
      context,
      canRespond: canPost && sent,
      canEdit: canEdit,
      canDelete: canDelete,
      isOwn: isOwn,
      isTextMessage: isTextMessage,
      isAttachment: isAttachment,
      galleryCount: galleryCount,
      facts: [
        if (isAttachment)
          MessageFact(
            icon: Icons.info_outline,
            child: Text(attachmentInfoText(l10n, displayEvent, attachmentKind)),
          ),
        MessageFact(
          icon: Icons.schedule_outlined,
          child: Text(switch (displayEvent.status) {
            EventStatus.error => l10n.chatNotSent,
            EventStatus.sending => l10n.chatSending,
            _ => l10n.chatSentAt(labels.dateTime(event.originServerTs)),
          }),
        ),
        if (!isOwn) SenderDeviceTile(event: event),
        if (isOwn) _SeenByTile(room: widget.room, event: event),
      ],
      onReact: (key) => _reactToMessage(event, timeline, key),
      onMoreReactions: () => _pickReaction(event, timeline),
    );
    if (!mounted) return;
    switch (action) {
      case MessageAction.reply:
        _startReply(event);
      case MessageAction.edit:
        _startEdit(event);
      case MessageAction.delete:
        await _deleteMessages(
          galleryEvents ?? [event],
          gallery: galleryEvents != null,
        );
      case MessageAction.share:
        await _shareAttachments(galleryEvents ?? [displayEvent]);
      case MessageAction.save:
        await _saveAttachments(galleryEvents ?? [displayEvent]);
      case MessageAction.copy:
        await Clipboard.setData(
          ClipboardData(text: displayBody(event, timeline)),
        );
        if (mounted) _snack(l10n.chatCopied);
      case MessageAction.report:
        await _reportMessage(event);
      case null:
        break;
    }
  }

  Future<void> _reportMessage(Event event) async {
    final sent = await showReportSheet(
      context,
      title: context.l10n.chatReportTitle,
      explanation: widget.room.isDirectChat
          ? context.l10n.chatReportExplainDirect
          : context.l10n.chatReportExplainGroup,
      onSend: (reason, note) => reportMessage(event, reason, note: note),
    );
    if (sent && mounted) _snack(context.l10n.commonReportSent);
  }

  Future<void> _reactToMessage(Event event, Timeline timeline, String key) =>
      toggleReactionWithFeedback(
        ScaffoldMessenger.of(context),
        context.l10n,
        event,
        timeline,
        key,
      );

  Future<void> _pickReaction(Event event, Timeline timeline) async {
    final key = await showSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: 320,
        child: EmojiPicker(
          onEmojiSelected: (category, emoji) =>
              Navigator.of(context).pop(emoji.emoji),
        ),
      ),
    );
    if (key == null || !mounted) return;
    await _reactToMessage(event, timeline, key);
  }

  Future<void> _shareAttachments(List<Event> events) =>
      shareAttachmentsWithFeedback(
        ScaffoldMessenger.of(context),
        context.l10n,
        events,
      );

  Future<void> _saveAttachments(List<Event> events) =>
      saveAttachmentsWithFeedback(
        ScaffoldMessenger.of(context),
        context.l10n,
        events,
      );

  Future<void> _keepingUploadAlive(Future<void> Function() body) async {
    final service = UploadForegroundService.instance;
    await service.acquire();
    try {
      await body();
    } finally {
      await service.release();
    }
  }

  _SendSession _sendSession() => _SendSession(
    messenger: ScaffoldMessenger.of(context),
    l10n: context.l10n,
    reduceMediaSize: ref.read(reduceMediaSizeProvider),
    uploadProgress: ref.read(uploadProgressHttpClientProvider).onUploadProgress,
    discarded: ref.read(discardedSendsProvider),
  );

  Future<void> _withSendProgress(
    _SendSession session,
    PendingAttachmentSend pending,
    Future<void> Function(_SendProgressSink progress) send,
  ) {
    return _keepingUploadAlive(() async {
      var current = pending;
      void publish(PendingAttachmentSend next) {
        current = next;
        if (mounted) _pendingSend.value = next;
        unawaited(
          UploadForegroundService.instance.updateProgress(
            label: next.progressLabel(session.l10n),
            fraction: next.progress,
          ),
        );
      }

      void advance(SendStage stage, double? fraction) =>
          publish(current.withStage(stage, fraction));

      publish(pending);
      final sub = session.uploadProgress.listen(
        (fraction) => advance(SendStage.uploading, fraction),
      );
      try {
        await send(
          _SendProgressSink(
            compression: (fraction) => advance(SendStage.compressing, fraction),
            preview: (bytes, {width, height}) => publish(
              current.withPreview(bytes, width: width, height: height),
            ),
          ),
        );
      } finally {
        await sub.cancel();
        if (mounted) _pendingSend.value = null;
      }
    });
  }

  Future<void> _guardedSend(
    _SendSession session,
    String txid,
    Future<void> Function() send, {
    required VoidCallback onFailed,
  }) async {
    try {
      await send();
    } on MediaProcessingException catch (e) {
      session.say(e.message);
    } on FileTooBigMatrixException catch (e) {
      await discardSendPlaceholder(widget.room, txid);
      session.say(tooLargeToSendMessage(session.l10n, e));
    } catch (e, s) {
      reportCaught('send attachment', e, s);
      await discardSendPlaceholder(widget.room, txid);
      onFailed();
    }
  }

  ({double? maxDimension, int? quality}) _pickerImageLimits() =>
      pickerImageLimits(
        nativeImageResize: ref
            .read(platformCapabilitiesProvider)
            .nativeImageResize,
        reduceMediaSize: ref.read(reduceMediaSizeProvider),
      );

  Future<void> _pickAndSendImages(ImageSource source) async {
    final session = _sendSession();
    final limits = _pickerImageLimits();
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: limits.maxDimension,
      maxHeight: limits.maxDimension,
      imageQuality: limits.quality,
    );
    if (file == null) return;
    await _composeAndSend(session, [file], isVideo: (_) => false);
  }

  Future<void> _pickAndSendGalleryMedia() async {
    final session = _sendSession();
    final limits = _pickerImageLimits();
    final picked = await ImagePicker().pickMultipleMedia(
      maxWidth: limits.maxDimension,
      maxHeight: limits.maxDimension,
      imageQuality: limits.quality,
    );
    await _composeAndSend(session, picked);
  }

  Future<void> _pickAndSendVideo(ImageSource source) async {
    final session = _sendSession();
    final picked = await ImagePicker().pickVideo(source: source);
    if (picked == null) return;
    await _composeAndSend(session, [picked], isVideo: (_) => true);
  }

  Future<void> _composeAndSend(
    _SendSession session,
    List<XFile> picked, {
    bool Function(XFile file) isVideo = looksLikeVideo,
  }) => _withCopies([for (final file in picked) file.path], () async {
    if (picked.isEmpty || !mounted) return;
    final composed = await _compose(picked, isVideo);
    if (composed == null) return;
    await _sendComposed(session, composed);
  });

  Future<List<ComposedMedia>?> _compose(
    List<XFile> picked,
    bool Function(XFile file) isVideo,
  ) async {
    final navigator = Navigator.of(context);
    final videos = picked.where(isVideo).toList();
    if (videos.isEmpty) {
      final images = await navigator.push<List<ComposedImage>>(
        MaterialPageRoute(
          builder: (_) => ImageCaptionComposerPage(
            images: [
              for (final file in picked) (path: file.path, name: file.name),
            ],
          ),
        ),
      );
      return images?.map(ComposedImageResult.new).toList();
    }
    if (picked.length == 1) {
      final video = await navigator.push<ComposedVideo>(
        MaterialPageRoute(
          builder: (_) => VideoCaptionComposerPage(
            path: videos.single.path,
            name: videos.single.name,
          ),
        ),
      );
      return video == null ? null : [ComposedVideoResult(video)];
    }
    return navigator.push<List<ComposedMedia>>(
      MaterialPageRoute(
        builder: (_) => MediaCaptionComposerPage(
          items: [
            for (final file in picked)
              isVideo(file)
                  ? PickedVideo(path: file.path, name: file.name)
                  : PickedImage(path: file.path, name: file.name),
          ],
        ),
      ),
    );
  }

  Future<void> _sendComposed(
    _SendSession session,
    List<ComposedMedia> composed,
  ) {
    final groupId = composed.length > 1
        ? widget.room.client.generateUniqueTransactionId()
        : null;
    return _keepingUploadAlive(
      () => session.discarded.whileSending([groupId], () async {
        for (final (i, media) in composed.indexed) {
          if (session.discarded.contains(widget.room, [groupId])) break;
          final gallery = groupId == null
              ? null
              : GalleryGroupRef(id: groupId, index: i, count: composed.length);
          await switch (media) {
            ComposedImageResult(:final image) => _sendPhoto(
              session,
              image,
              gallery: gallery,
            ),
            ComposedVideoResult(:final video) => _sendVideoAttachment(
              session,
              video,
              gallery: gallery,
            ),
          };
        }
      }),
    );
  }

  Future<void> _applyPendingShare(InboundShare share) async {
    if (!mounted) return;
    final text = share.text;
    if (text != null) _showInComposer(text);
    if (share.files.isEmpty) return;

    final session = _sendSession();
    final copies = await copySharedFilesToCache(share.files);
    await _withCopies([for (final copy in copies) copy.path], () async {
      if (!mounted) return;
      final unopened = share.files.length - copies.length;
      if (unopened > 0) session.say(session.l10n.chatUnopenedShares(unopened));
      final (:media, :others) = await partitionSharedFiles(copies);
      if (media.isNotEmpty) await _composeAndSend(session, media);
      for (final file in others) {
        await _sendFile(
          session,
          await file.readAsBytes(),
          name: file.name,
          mimeType: file.mimeType,
        );
      }
    });
  }

  Future<void> _withCopies(
    List<String> paths,
    Future<void> Function() body,
  ) async {
    _copies.addAll(paths);
    for (final path in paths) {
      _copyUses.update(path, (uses) => uses + 1, ifAbsent: () => 1);
    }
    try {
      await body();
    } finally {
      for (final path in paths) {
        final uses = _copyUses[path]! - 1;
        if (uses > 0) {
          _copyUses[path] = uses;
        } else {
          _copyUses.remove(path);
        }
      }
      await _releaseCopies(paths);
    }
  }

  Future<void> _releaseCopies(List<String> paths) async {
    final unused = [
      for (final path in paths)
        if (_copies.contains(path) &&
            !_copyUses.containsKey(path) &&
            !(mounted && _failedSends.any((failed) => failed.path == path)))
          path,
    ];
    _copies.removeAll(unused);
    await Future.wait(unused.map(discardTemporaryCopy));
  }

  Future<void> _pickAndSendFile() async {
    final session = _sendSession();
    final files = await trackPickerCopy(
      (onFileLoading) => FilePicker.pickFiles(onFileLoading: onFileLoading),
      onCopying: (copying) {
        if (mounted) setState(() => _gettingFile = copying);
      },
    );
    await _withCopies([for (final file in files) ?file.path], () async {
      for (final file in files) {
        await _sendFile(session, await file.readAsBytes(), name: file.name);
      }
    });
  }

  Future<void> _sendVideoAttachment(
    _SendSession session,
    ComposedVideo composed, {
    GalleryGroupRef? gallery,
  }) {
    final txid = widget.room.client.generateUniqueTransactionId();
    return _guardedSend(
      session,
      txid,
      () => _withSendProgress(
        session,
        PendingAttachmentSend(
          eventId: txid,
          width: composed.width,
          height: composed.height,
          kind: SendMediaKind.video,
        ),
        (progress) async {
          final prepared = await prepareVideoForSend(
            composed.path,
            reduceMediaSize: session.reduceMediaSize,
            fallbackWidth: composed.width,
            fallbackHeight: composed.height,
            fallbackDurationMs: composed.durationMs,
            onThumbnail: (thumbnail) => progress.preview(
              thumbnail.bytes,
              width: thumbnail.width,
              height: thumbnail.height,
            ),
            onProgress: progress.compression,
          );
          await _sendFileEvent(
            session,
            prepared.file,
            txid: txid,
            thumbnail: prepared.thumbnail,
            extraContent: _attachmentExtraContent(
              caption: composed.caption,
              gallery: gallery,
            ),
            galleryId: gallery?.id,
          );
        },
      ),
      onFailed: () => _recordFailedSend(
        FailedMediaSend(gallery: gallery, video: composed),
        session,
      ),
    );
  }

  Future<void> _sendPhoto(
    _SendSession session,
    ComposedImage image, {
    GalleryGroupRef? gallery,
  }) {
    final txid = widget.room.client.generateUniqueTransactionId();
    return _guardedSend(
      session,
      txid,
      () async {
        final bytes = await File(image.path).readAsBytes();
        await _withSendProgress(
          session,
          PendingAttachmentSend(
            eventId: txid,
            previewBytes: bytes,
            kind: SendMediaKind.photo,
          ),
          (progress) async {
            final prepared = await prepareImageForSend(
              bytes,
              reduceMediaSize: session.reduceMediaSize,
              onProgress: progress.compression,
            );
            await _sendFileEvent(
              session,
              prepared.file,
              txid: txid,
              thumbnail: prepared.thumbnail,
              extraContent: _attachmentExtraContent(
                caption: image.caption,
                gallery: gallery,
              ),
              galleryId: gallery?.id,
            );
          },
        );
      },
      onFailed: () => _recordFailedSend(
        FailedMediaSend(gallery: gallery, photo: image),
        session,
      ),
    );
  }

  bool _isDiscarded(_SendSession session, String txid, String? galleryId) =>
      session.discarded.contains(widget.room, [txid, galleryId]);

  Future<void> _sendFileEvent(
    _SendSession session,
    MatrixFile file, {
    required String txid,
    MatrixImageFile? thumbnail,
    Map<String, dynamic>? extraContent,
    String? galleryId,
  }) async {
    if (_isDiscarded(session, txid, galleryId)) return;
    await _sendThenDropIfDiscarded(
      session,
      txid: txid,
      galleryId: galleryId,
      send: () => widget.room.sendFileEvent(
        file,
        txid: txid,
        thumbnail: thumbnail,
        extraContent: extraContent,
      ),
    );
  }

  Future<void> _sendThenDropIfDiscarded(
    _SendSession session, {
    required String txid,
    required String? galleryId,
    required Future<String?> Function() send,
  }) => session.discarded.whileSending([txid, galleryId], () async {
    final eventId = await send();
    if (!_isDiscarded(session, txid, galleryId)) return;
    try {
      if (eventId == null) {
        await discardSendPlaceholder(widget.room, txid);
      } else {
        await widget.room.redactEvent(eventId);
      }
    } catch (e, s) {
      reportCaught('delete a message that landed after its delete', e, s);
      session.say(
        galleryId == null
            ? session.l10n.chatDeleteOneFailed
            : session.l10n.chatDeleteManyFailed,
      );
    } finally {
      await session.discarded.remove(widget.room, txid);
    }
  });

  Future<void> _sendFile(
    _SendSession session,
    Uint8List bytes, {
    required String name,
    String? mimeType,
  }) {
    final txid = widget.room.client.generateUniqueTransactionId();
    return _guardedSend(
      session,
      txid,
      () => _withSendProgress(
        session,
        PendingAttachmentSend(eventId: txid, kind: SendMediaKind.file),
        (_) => _sendFileEvent(
          session,
          MatrixFile.fromMimeType(bytes: bytes, name: name, mimeType: mimeType),
          txid: txid,
        ),
      ),
      onFailed: () => session.say(session.l10n.chatNotSentTryAgain),
    );
  }

  Map<String, dynamic>? _attachmentExtraContent({
    required String? caption,
    required GalleryGroupRef? gallery,
  }) {
    final content = <String, dynamic>{
      if (caption != null && caption.isNotEmpty) 'body': caption,
      if (gallery != null)
        ...galleryGroupContent(
          id: gallery.id,
          index: gallery.index,
          count: gallery.count,
        ),
    };
    return content.isEmpty ? null : content;
  }

  void _recordFailedSend(FailedMediaSend failed, _SendSession session) {
    if (session.discarded.contains(widget.room, [failed.gallery?.id])) return;
    if (!mounted) {
      session.say(session.l10n.chatNotSentTryAgain);
      return;
    }
    setState(() => _failedSends.add(failed));
  }

  Future<void> _retryFailedSend(FailedMediaSend failed) async {
    if (!_failedSends.contains(failed)) return;
    final session = _sendSession();
    setState(() => _failedSends.remove(failed));
    await _withCopies([?failed.path], () async {
      switch (failed) {
        case FailedMediaSend(photo: final photo?):
          await _sendPhoto(session, photo, gallery: failed.gallery);
        case FailedMediaSend(video: final video?):
          await _sendVideoAttachment(session, video, gallery: failed.gallery);
      }
    });
  }

  Future<void> _resend(Event event) async {
    final session = _sendSession();
    final (:txid, :galleryId) = sendIdentity(event);
    if (_isDiscarded(session, txid, galleryId)) {
      await runBestEffort(
        () => _discardUnsent(session.discarded, event),
        label: 'discard a deleted send',
      );
      return;
    }
    await runBestEffort(
      () => _sendThenDropIfDiscarded(
        session,
        txid: txid,
        galleryId: galleryId,
        send: () => resendUnsent(event),
      ),
      label: 'sendAgain',
    );
  }

  void _retryAfterReconnect() {
    _markLatestRead();
    _resumeHistory();
    for (final failed in List<FailedMediaSend>.of(_failedSends)) {
      unawaited(_retryFailedSend(failed));
    }
    final timeline = _timeline;
    if (timeline == null) return;
    for (final event in notSentOwnEvents(timeline)) {
      unawaited(_resend(event));
    }
  }

  Future<void> _showAttachmentMenu() async {
    final choice = await showSheet<_Attachment>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(context.l10n.commonTakePhoto),
              onTap: () => Navigator.of(context).pop(_Attachment.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(context.l10n.commonChooseFromGallery),
              onTap: () => Navigator.of(context).pop(_Attachment.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: Text(context.l10n.chatRecordVideo),
              onTap: () => Navigator.of(context).pop(_Attachment.videoCamera),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_outlined),
              title: Text(context.l10n.chatChooseFile),
              onTap: () => Navigator.of(context).pop(_Attachment.file),
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(context.l10n.chatLocation),
              onTap: () => Navigator.of(context).pop(_Attachment.location),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    try {
      switch (choice) {
        case _Attachment.camera:
          await _pickAndSendImages(ImageSource.camera);
        case _Attachment.gallery:
          await _pickAndSendGalleryMedia();
        case _Attachment.videoCamera:
          await _pickAndSendVideo(ImageSource.camera);
        case _Attachment.file:
          await _pickAndSendFile();
        case _Attachment.location:
          await _sendLocation();
      }
    } catch (e, s) {
      if (!isPickerAccessDenied(e)) reportCaught('attach ${choice.name}', e, s);
      if (mounted) _snack(_attachmentFailure(choice, e));
    }
  }

  String _attachmentFailure(_Attachment choice, Object error) {
    final l10n = context.l10n;
    final code = error is PlatformException ? error.code : null;
    return switch (choice) {
      _Attachment.camera || _Attachment.videoCamera =>
        code == 'camera_access_denied'
            ? l10n.chatCameraAccessDenied
            : l10n.chatCameraDidNotOpen,
      _Attachment.gallery =>
        code == 'photo_access_denied'
            ? l10n.chatPhotoAccessDenied
            : l10n.chatPhotosDidNotOpen,
      _Attachment.file => l10n.chatFilesDidNotOpen,
      _Attachment.location => l10n.chatLocationNotSent,
    };
  }

  Future<void> _sendLocation() async {
    final sharing = ref.read(liveLocationSharingProvider);
    final room = widget.room;
    final choice = await showLocationShareSheet(
      context,
      liveLocation: ref.read(platformCapabilitiesProvider).liveLocation
          ? liveLocationAvailability(
              room,
              sharingHere: sharing.isSharingIn(room.id),
            )
          : LiveLocationAvailability.unavailable,
      inChat: room.isDirectChat,
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case SendPin(:final geo):
        try {
          await sendLocationPin(room, geo, at: DateTime.now());
        } catch (e, s) {
          reportCaughtType('send location pin', e, s);
          if (mounted) _snack(context.l10n.chatLocationNotSent);
        }
      case ShareLive(:final first, :final duration):
        try {
          await sharing.start(room, duration, first);
        } on LiveShareStartException catch (error) {
          if (mounted) {
            _snack(liveShareStartFailureText(context.l10n, error.reason));
          }
        }
    }
  }

  static const _slideToCancelThreshold = 80.0;

  bool get _recordingWillCancel =>
      _recordingSlideOffset < -_slideToCancelThreshold;

  Duration get _elapsedRecordingDuration {
    final startedAt = _recordingStartedAt;
    return startedAt == null
        ? Duration.zero
        : clock.now().difference(startedAt);
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          _snack(context.l10n.chatMicrophoneAccessNeeded);
        }
        return;
      }
      final setup = voiceRecordingSetup(ref.read(platformCapabilitiesProvider));
      final dir = await getTemporaryDirectory();
      final path = p.join(
        dir.path,
        'voice-${DateTime.now().millisecondsSinceEpoch}.${setup.extension}',
      );
      await _recorder.start(setup.config, path: path);
      if (!mounted) return;
      _waveformSamples.clear();
      _recordingStartedAt = clock.now();
      setState(() {
        _recording = true;
        _recordingPath = path;
        _recordingDuration.value = Duration.zero;
        _recordingSlideOffset = 0;
      });
      _recordingTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          _recordingDuration.value += const Duration(seconds: 1);
        }
      });
      _amplitudeSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amplitude) {
            _waveformSamples.add(normalizedAmplitude(amplitude.current));
          });
    } catch (e, s) {
      reportCaught('start recording', e, s);
      _tapToggleRecording = false;
      _micHeld = false;
      if (mounted) {
        setState(() {});
        _snack(context.l10n.chatRecordingDidNotStart);
      }
    }
  }

  void _onMicPointerDown(PointerDownEvent event) {
    if (_tapToggleRecording) return;
    _micDownPosition = event.position;
    _micHeld = false;
    _micHoldTimer = Timer(_micHoldThreshold, () {
      _micHoldTimer = null;
      _micHeld = true;
      unawaited(_startRecording());
    });
  }

  void _onMicPointerMove(PointerMoveEvent event) {
    if (!_micHeld) return;
    final down = _micDownPosition;
    if (down == null) return;
    _onRecordingDrag(event.position - down);
  }

  Future<void> _onMicPointerUp(PointerUpEvent event) async {
    _micDownPosition = null;

    if (_tapToggleRecording) {
      _tapToggleRecording = false;
      await _stopAndSendRecording();
      return;
    }
    if (_micHoldTimer != null) {
      _micHoldTimer!.cancel();
      _micHoldTimer = null;
      _tapToggleRecording = true;
      await _startRecording();
      return;
    }
    if (_micHeld) {
      _micHeld = false;
      await _onRecordingReleased();
    }
  }

  Future<void> _onMicPointerCancel(PointerCancelEvent event) async {
    _micDownPosition = null;
    _micHoldTimer?.cancel();
    _micHoldTimer = null;
    final wasRecording = _micHeld || _tapToggleRecording;
    _micHeld = false;
    _tapToggleRecording = false;
    if (wasRecording) await _cancelRecording();
  }

  void _onRecordingDrag(Offset offsetFromOrigin) {
    if (!mounted) return;
    setState(() => _recordingSlideOffset = offsetFromOrigin.dy);
  }

  static const _minHoldToSend = Duration(milliseconds: 300);

  Future<void> _onRecordingReleased() async {
    if (_recordingWillCancel) {
      await _cancelRecording();
      return;
    }
    if (_elapsedRecordingDuration < _minHoldToSend) {
      if (mounted) setState(() => _tapToggleRecording = true);
      return;
    }
    await _stopAndSendRecording();
  }

  Future<void> _stopRecordingSampling() async {
    _recordingTicker?.cancel();
    _recordingTicker = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
  }

  void _clearRecordingState() {
    setState(() {
      _recording = false;
      _recordingPath = null;
      _recordingSlideOffset = 0;
      _tapToggleRecording = false;
    });
  }

  Future<void> _cancelRecording() async {
    await _stopRecordingSampling();
    await _recorder.stop();
    final path = _recordingPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    _recordingStartedAt = null;
    if (!mounted) return;
    _clearRecordingState();
  }

  Future<void> _stopAndSendRecording() async {
    await _stopRecordingSampling();
    final path = await _recorder.stop();
    final duration = _elapsedRecordingDuration;
    final waveform = resampleWaveform(_waveformSamples);
    _recordingStartedAt = null;
    if (mounted) _clearRecordingState();
    if (path == null) return;

    final file = File(path);
    final recorded = await file.readAsBytes();
    await file.delete();
    if (duration < const Duration(milliseconds: 100)) return;
    if (!mounted) return;

    final bytes = voiceRecordingSetup(ref.read(platformCapabilitiesProvider))
        .toOggOpus(recorded);
    if (bytes == null) {
      _snack(context.l10n.chatVoiceMessageNotSent);
      return;
    }

    final session = _sendSession();
    try {
      await _sendFileEvent(
        session,
        MatrixFile(
          bytes: bytes,
          name: 'Voice message.ogg',
          mimeType: 'audio/ogg',
        ),
        txid: widget.room.client.generateUniqueTransactionId(),
        extraContent: {
          'org.matrix.msc3245.voice': {},
          'org.matrix.msc1767.audio': {
            'duration': duration.inMilliseconds,
            'waveform': waveform,
          },
        },
      );
    } catch (e, s) {
      reportCaught('send voice message', e, s);
      session.say(session.l10n.chatVoiceMessageNotSent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showHiddenMessages = ref.watch(showHiddenMessagesProvider);
    final capabilities = ref.watch(platformCapabilitiesProvider);
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
        menuBuilder: (_) => [
          PopupMenuItem(
            onTap: _openRoomInfo,
            child: Text(
              widget.room.isDirectChat ? l10n.chatChatInfo : l10n.chatRoomInfo,
            ),
          ),
          if (!widget.room.isDirectChat && widget.room.canInvite)
            PopupMenuItem(
              onTap: () => unawaited(_addMembers()),
              child: Text(l10n.chatAddMembers),
            ),
          if (capabilities.homeScreenShortcuts)
            PopupMenuItem(
              onTap: () => unawaited(_addToHomeScreen()),
              child: Text(l10n.chatAddToHomeScreen),
            ),
          if (canReloadRoomTimeline(widget.room))
            PopupMenuItem(
              onTap: () => unawaited(_reinitializeConversation()),
              child: Text(l10n.chatReloadMessages),
            ),
          PopupMenuItem(
            onTap: () async {
              if (!await confirmAndExitRoom(
                context,
                widget.room,
                endCallsIn: ref.read(endCallsInProvider),
              )) {
                return;
              }
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(roomExitLabel(widget.room, l10n)),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            const ChatWallpaperBackground(),
            Positioned.fill(
              child: Column(
                children: [
                  IdentityChangeBanner(room: widget.room),
                  UnvouchedDeviceBanner(room: widget.room),
                  PendingInviteBanner(room: widget.room),
                  JoinRequestsBanner(room: widget.room),
                  if (showActiveCallBanner)
                    _ActiveCallBanner(
                      call: activeRoomCall,
                      onJoin: () => _joinActiveCall(activeRoomCall),
                    ),
                  LiveLocationBanner(room: widget.room),
                  Expanded(
                    child: timeline == null
                        ? _TimelinePlaceholder(loading: routeSettled)
                        : Stack(
                            children: [
                              MessageListView(
                                room: widget.room,
                                timeline: timeline,
                                controller: _scrollController,
                                showHiddenMessages: showHiddenMessages,
                                canRespond: canPost,
                                failedSends: _failedSends,
                                pendingSend: _pendingSend,
                                replyTargets: _replyTargets,
                                onLongPress: (event, gallery) =>
                                    _showMessageActions(
                                      event,
                                      galleryEvents: gallery,
                                    ),
                                onDoubleTap: (event) => _reactToMessage(
                                  event,
                                  timeline,
                                  _doubleTapReaction,
                                ),
                                onSwipeReply: _startReply,
                                onResend: _resend,
                                onRetryFailedSend: _retryFailedSend,
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
                            isRecording: _recording,
                            recordingDuration: _recordingDuration,
                            recordingWillCancel: _recordingWillCancel,
                            tapToggleRecording: _tapToggleRecording,
                            onMicPointerDown: _onMicPointerDown,
                            onMicPointerMove: _onMicPointerMove,
                            onMicPointerUp: _onMicPointerUp,
                            onMicPointerCancel: _onMicPointerCancel,
                            onCancelRecording: _cancelRecording,
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

class _ActiveCallBanner extends StatelessWidget {
  final ActiveRoomCall call;
  final VoidCallback onJoin;

  const _ActiveCallBanner({required this.call, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isVideo = call.kind == CallKind.video.name;
    return Material(
      color: scheme.secondaryContainer,
      child: InkWell(
        onTap: onJoin,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                isVideo ? Icons.videocam_outlined : Icons.call_outlined,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isVideo
                      ? context.l10n.chatVideoCallInProgress
                      : context.l10n.chatVoiceCallInProgress,
                  style: TextStyle(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              FilledButton.tonal(
                onPressed: onJoin,
                child: Text(context.l10n.commonJoin),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Attachment { camera, gallery, videoCamera, file, location }

class _SeenByTile extends StatefulWidget {
  final Room room;
  final Event event;

  const _SeenByTile({required this.room, required this.event});

  @override
  State<_SeenByTile> createState() => _SeenByTileState();
}

class _SeenByTileState extends State<_SeenByTile> {
  StreamSubscription<SyncUpdate>? _syncSub;
  StreamSubscription<({String roomId, StrippedStateEvent state})>?
  _roomStateSub;
  bool _roomStateRebuildPending = false;

  @override
  void initState() {
    super.initState();
    _syncSub = widget.room.client.onSync.stream.listen((_) {
      if (mounted) setState(() {});
    });
    _roomStateSub = widget.room.client.onRoomState.stream.listen((_) {
      if (_roomStateRebuildPending || !mounted) return;
      _roomStateRebuildPending = true;
      scheduleMicrotask(() {
        _roomStateRebuildPending = false;
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _roomStateSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seen = seenByOthers(widget.room, widget.event);
    final l10n = context.l10n;
    final labels = DateLabels.of(context);
    final seenBy = seen
        .map(
          (s) => l10n.chatSeenByEntry(
            s.user.calcDisplayname(),
            labels.dateTime(s.at),
          ),
        )
        .join('\n');
    return MessageFact(
      icon: seen.isEmpty ? Icons.done : Icons.done_all,
      child: Text(seen.isEmpty ? l10n.chatNotSeenYet : l10n.chatSeenBy(seenBy)),
    );
  }
}

class _SendSession {
  final ScaffoldMessengerState messenger;
  final AppLocalizations l10n;
  final bool reduceMediaSize;
  final Stream<double> uploadProgress;
  final DiscardedSends discarded;

  const _SendSession({
    required this.messenger,
    required this.l10n,
    required this.reduceMediaSize,
    required this.uploadProgress,
    required this.discarded,
  });

  void say(@displayText String message) =>
      messenger.showSnackBar(SnackBar(content: Text(message)));
}

class _SendProgressSink {
  final void Function(double fraction) compression;
  final void Function(Uint8List bytes, {int? width, int? height}) preview;

  const _SendProgressSink({required this.compression, required this.preview});
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
