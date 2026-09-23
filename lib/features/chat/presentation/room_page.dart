import 'dart:async';
import 'dart:io';

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

import '../../../core/calls/active_call_provider.dart';
import '../../../core/calls/matrixrtc/active_room_call.dart';
import '../../../core/calls/matrixrtc/call_member_state.dart';
import '../../../core/calls/matrixrtc/call_session.dart';
import '../../../core/calls/matrixrtc/call_unread_correction_provider.dart';
import '../../../core/calls/models/call_kind.dart';
import '../../../core/calls/notifications/call_notification_service.dart';
import '../../../core/errors/best_effort.dart';
import '../../../core/location/location_message.dart';
import '../../../core/matrix/abuse_report.dart';
import '../../../core/matrix/attachment_action_buttons.dart';
import '../../../core/matrix/attachment_actions.dart';
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
import '../../../core/matrix/reactions.dart';
import '../../../core/matrix/read_receipts.dart';
import '../../../core/matrix/room_exit.dart';
import '../../../core/matrix/room_invite.dart';
import '../../../core/matrix/room_permission.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/matrix/send_failure.dart';
import '../../../core/matrix/send_progress.dart';
import '../../../core/matrix/upload_foreground_service.dart';
import '../../../core/matrix/video_send_preparation.dart';
import '../../../core/security/recovery_code.dart';
import '../../../core/security/recovery_code_leak.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/share/inbound_share.dart';
import '../../../core/shortcuts/home_screen_shortcut.dart';
import '../../../core/ui/route_settled.dart';
import '../../calls/presentation/call_page.dart';
import '../../location/presentation/location_share_sheet.dart';
import '../../reports/presentation/report_sheet.dart';
import '../../room_info/presentation/room_info_page.dart';
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

String _formatDateTime(DateTime time) {
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

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
  Event? _replyingToEvent;

  StreamSubscription<SyncUpdate>? _syncSub;
  StreamSubscription<({String roomId, StrippedStateEvent state})>?
  _roomStateSub;
  bool _roomStateRebuildPending = false;
  String? _lastMarkedReadEventId;

  final _pendingSend = ValueNotifier<PendingAttachmentSend?>(null);
  late var _replyTargets = ReplyTargetCache(widget.room.getEventById);
  bool _activeCallBannerShown = false;

  final List<FailedMediaSend> _failedSends = [];

  final _recorder = AudioRecorder();
  bool _recording = false;
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
      CallNotificationService.instance.cancelMessageNotification(
        widget.room.id,
      ),
    );
    _scrollController.addListener(_maybeLoadMoreHistory);
    _scrollController.addListener(_updateScrollToBottomVisibility);
    unawaited(_loadTimeline());
    _syncSub = widget.room.client.onSync.stream.listen((update) {
      if (!mounted) return;
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = isRoomForeground(state);
    if (isForeground == _isForeground) return;
    _isForeground = isForeground;
    if (isForeground) {
      _currentlyOpenRoomNotifier.set(widget.room.id);
      unawaited(
        CallNotificationService.instance.cancelMessageNotification(
          widget.room.id,
        ),
      );
      _markLatestRead();
    } else {
      if (_currentlyOpenRoomNotifier.current == widget.room.id) {
        _currentlyOpenRoomNotifier.set(null);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_maybeLoadMoreHistory);
    _scrollController.removeListener(_updateScrollToBottomVisibility);
    _scrollController.dispose();
    _pendingSend.dispose();
    _recordingDuration.dispose();
    _showScrollToBottom.dispose();
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
    if (routeSettled) _applyPendingTimeline();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addMembers() async {
    final room = widget.room;
    final userId = await showLocalUsernameDialog(
      context,
      client: room.client,
      title: 'Add members',
      actionLabel: 'Invite',
    );
    if (userId == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await room.invite(userId);
      messenger.showSnackBar(const SnackBar(content: Text('Invitation sent')));
    } catch (e) {
      logCaught('invite', e);
      messenger.showSnackBar(
        const SnackBar(content: Text('Invitation not sent. Try again.')),
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
    } catch (_) {
      return null;
    }
  }

  Future<void> _addToHomeScreen() async {
    final room = widget.room;
    final messenger = ScaffoldMessenger.of(context);
    final iconBytes = await _fetchRoomAvatarBytes();
    try {
      final requested = await pinRoomShortcut(
        roomId: room.id,
        label: roomTitle(room),
        iconBytes: iconBytes,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            requested
                ? 'Confirm on your home screen to finish adding it'
                : 'This launcher does not support home screen shortcuts',
          ),
        ),
      );
    } catch (e) {
      logCaught('add shortcut', e);
      messenger.showSnackBar(
        const SnackBar(content: Text('Shortcut not added. Try again.')),
      );
    }
  }

  Future<void> _reinitializeConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reload messages?'),
        content: const Text(
          'Clears the messages saved on this device for this chat and '
          'downloads them again. Nothing is deleted on the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reload'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _timeline?.cancelSubscriptions();
    setState(() {
      _timeline = null;
      _replyTargets = ReplyTargetCache(widget.room.getEventById);
    });
    await widget.room.client.database.deleteTimelineForRoom(widget.room.id);
    widget.room.lastEvent = null;
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
        label: 'setReadMarker ${widget.room.id}',
      ).then((ok) {
        if (!ok && _lastMarkedReadEventId == eventId) {
          _lastMarkedReadEventId = null;
        }
      }),
    );
    ref.read(callUnreadCorrectionProvider.notifier).clearFor(widget.room.id);
  }

  void _maybeLoadMoreHistory() {
    final timeline = _timeline;
    if (timeline == null || !timeline.canRequestHistory) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 400) return;
    unawaited(runBestEffort(timeline.requestHistory, label: 'requestHistory'));
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
    _input.clear();
    setState(() {
      _editingEvent = null;
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
      label: 'sendTextEvent ${widget.room.id}',
    );
  }

  Future<void> _startCall(CallKind kind) async {
    if (ref.read(activeCallProvider) != null) {
      _snack('You are already in a call');
      return;
    }
    if (!canPublishCallMemberState(widget.room)) {
      _snack('You do not have permission to start calls in this room');
      return;
    }
    if (!hasSomeoneToCall(widget.room)) {
      _snack('Nobody has joined this chat yet');
      return;
    }
    if (ref.read(isOfflineProvider).value ?? false) {
      _snack('No connection. Try again once back online.');
      return;
    }
    if (ref.read(confirmBeforeCallingProvider)) {
      final name = roomTitle(widget.room);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Call $name?'),
          content: Text(
            kind == CallKind.video
                ? 'Start a video call.'
                : 'Start a voice call.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Call'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final session = CallSession.startOutgoing(
      widget.room,
      kind,
      lowDataMode: ref.read(lowDataCallsProvider),
    );
    ref.read(activeCallProvider.notifier).set(session);
    unawaited(_pushCallPage(session));
  }

  Future<void> _pushCallPage(CallSession session) =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => CallPage(session: session)));

  Future<void> _joinActiveCall(ActiveRoomCall call) async {
    if (ref.read(activeCallProvider) != null) return;
    if (!canPublishCallMemberState(widget.room)) {
      _snack('You do not have permission to join calls in this room');
      return;
    }
    if (ref.read(isOfflineProvider).value ?? false) {
      _snack('No connection. Try again once back online.');
      return;
    }
    final session = CallSession.forIncoming(
      room: widget.room,
      callId: call.callId,
      kind: CallKind.values.asNameMap()[call.kind] ?? CallKind.voice,
      lowDataMode: ref.read(lowDataCallsProvider),
    );
    ref.read(activeCallProvider.notifier).set(session);
    unawaited(_pushCallPage(session));
    unawaited(session.accept().catchError((_) {}));
  }

  void _startReply(Event event) {
    setState(() {
      _editingEvent = null;
      _replyingToEvent = event;
    });
  }

  void _startEdit(Event event) {
    setState(() {
      _replyingToEvent = null;
      _editingEvent = event;
      _input.text = displayBody(event, _timeline!);
    });
  }

  void _cancelCompose() {
    setState(() {
      _editingEvent = null;
      _replyingToEvent = null;
      _input.clear();
    });
  }

  Future<void> _deleteMessage(Event event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('Deletes it for everyone. Nobody can undo this.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.room.redactEvent(event.eventId);
    } catch (e) {
      logCaught('delete message', e);
      messenger.showSnackBar(
        const SnackBar(content: Text('Message not deleted. Try again.')),
      );
    }
  }

  Future<void> _showMessageActions(
    Event event, {
    List<Event>? galleryEvents,
  }) async {
    final timeline = _timeline;
    if (timeline == null || event.redacted) return;
    final isOwn = event.senderId == widget.room.client.userID;
    final canDelete = isOwn || widget.room.canRedact;
    final displayEvent = event.getDisplayEvent(timeline);
    final canPost = canPostInRoom(widget.room);
    final canEdit =
        canPost &&
        isOwn &&
        !event.hasAttachment &&
        displayEvent.messageType == MessageTypes.Text;
    final attachmentKind = classifyAttachment(displayEvent);
    final isAttachment =
        attachmentKind != AttachmentKind.none &&
        attachmentKind != AttachmentKind.location;
    final isTextMessage = !isAttachment;
    final galleryCount = galleryEvents?.length ?? 0;

    final action = await showMessageActionsSheet(
      context,
      canPost: canPost,
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
            child: Text(attachmentInfoText(displayEvent, attachmentKind)),
          ),
        MessageFact(
          icon: Icons.schedule_outlined,
          child: Text('Sent ${_formatDateTime(event.originServerTs)}'),
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
        await _deleteMessage(event);
      case MessageAction.share:
        await _shareAttachments(galleryEvents ?? [displayEvent]);
      case MessageAction.save:
        await _saveAttachments(galleryEvents ?? [displayEvent]);
      case MessageAction.copy:
        await Clipboard.setData(
          ClipboardData(text: displayBody(event, timeline)),
        );
        if (mounted) _snack('Copied');
      case MessageAction.report:
        await _reportMessage(event);
      case null:
        break;
    }
  }

  Future<void> _reportMessage(Event event) async {
    final sent = await showReportSheet(
      context,
      title: 'Report message',
      explanation: widget.room.isDirectChat
          ? 'The report goes to Zuno. It names the message and who sent it, '
                'not what it says. Zuno cannot read your messages, so '
                'describe what happened.'
          : 'The report goes to Zuno. It names the message and who sent it, '
                'not what it says. Room admins can remove messages and '
                'people. A report is for what they cannot fix.',
      onSend: (reason, note) => reportMessage(event, reason, note: note),
    );
    if (sent && mounted) _snack('Report sent');
  }

  Future<void> _reactToMessage(
    Event event,
    Timeline timeline,
    String key,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await toggleReaction(event, timeline, key);
    } catch (e) {
      logCaught('react', e);
      messenger.showSnackBar(
        const SnackBar(content: Text('Reaction not sent. Try again.')),
      );
    }
  }

  Future<void> _pickReaction(Event event, Timeline timeline) async {
    final key = await showModalBottomSheet<String>(
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
      shareAttachmentsWithFeedback(ScaffoldMessenger.of(context), events);

  Future<void> _saveAttachments(List<Event> events) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (events.length == 1) {
        final message = await saveAttachment(events.single);
        if (message != null) {
          messenger.showSnackBar(SnackBar(content: Text(message)));
        }
        return;
      }
      final saved = await saveAttachments(events);
      messenger.showSnackBar(
        SnackBar(
          content: Text(savedSummary(saved: saved, total: events.length)),
        ),
      );
    } catch (e) {
      logCaught('save attachment', e);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save. Try again.')),
      );
    }
  }

  Future<void> _keepingUploadAlive(Future<void> Function() body) async {
    final service = UploadForegroundService.instance;
    await service.acquire();
    try {
      await body();
    } finally {
      await service.release();
    }
  }

  Future<void> _withSendProgress(
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
            label: next.progressLabel,
            fraction: next.progress,
          ),
        );
      }

      void advance(SendStage stage, double? fraction) =>
          publish(current.withStage(stage, fraction));

      publish(pending);
      final sub = ref
          .read(uploadProgressHttpClientProvider)
          .onUploadProgress
          .listen((fraction) => advance(SendStage.uploading, fraction));
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
    String txid,
    Future<void> Function() send, {
    required void Function(Object error) onFailed,
  }) async {
    try {
      await send();
    } on MediaProcessingException catch (e) {
      _snack(e.message);
    } on FileTooBigMatrixException catch (e) {
      await discardSendPlaceholder(widget.room, txid);
      if (mounted) _snack(tooLargeToSendMessage(e));
    } catch (e) {
      await discardSendPlaceholder(widget.room, txid);
      onFailed(e);
    }
  }

  Future<void> _pickAndSendImages(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source);
    if (file == null || !mounted) return;
    await _sendImageBatch([file]);
  }

  Future<void> _sendImageBatch(List<XFile> picked) async {
    final images = await Future.wait(
      picked.map(
        (file) async => (bytes: await file.readAsBytes(), name: file.name),
      ),
    );
    if (!mounted) return;

    final composed = await Navigator.of(context).push<List<ComposedImage>>(
      MaterialPageRoute(
        builder: (_) => ImageCaptionComposerPage(images: images),
      ),
    );
    if (composed == null) return;

    final groupId = composed.length > 1 ? _newGalleryGroupId() : null;
    await _keepingUploadAlive(() async {
      for (var i = 0; i < composed.length; i++) {
        final image = composed[i];
        await _sendPhoto(
          image.bytes,
          caption: image.caption,
          gallery: groupId == null
              ? null
              : GalleryGroupRef(id: groupId, index: i, count: composed.length),
        );
      }
    });
  }

  String _newGalleryGroupId() =>
      widget.room.client.generateUniqueTransactionId();

  Future<void> _pickAndSendGalleryMedia() async {
    final picked = await ImagePicker().pickMultipleMedia();
    if (picked.isEmpty || !mounted) return;
    await _sendPickedMedia(picked);
  }

  Future<void> _sendPickedMedia(List<XFile> picked) async {
    final images = <XFile>[];
    final videos = <XFile>[];
    for (final file in picked) {
      (looksLikeVideo(file) ? videos : images).add(file);
    }

    if (videos.length > 1 || (images.isNotEmpty && videos.isNotEmpty)) {
      await _sendMixedMediaBatch(picked);
      return;
    }

    if (images.isNotEmpty) await _sendImageBatch(images);
    for (final video in videos) {
      if (!mounted) return;
      await _pickAndSendVideoFile(video);
    }
  }

  Future<void> _applyPendingShare(InboundShare share) async {
    if (!mounted) return;
    final text = share.text;
    if (text != null) {
      _input.text = text;
      _input.selection = TextSelection.collapsed(offset: text.length);
    }
    if (share.files.isEmpty) return;

    final copies = await copySharedFilesToCache(share.files);
    try {
      if (!mounted) return;
      final (:media, :others) = partitionSharedFiles(copies);
      if (media.isNotEmpty) await _sendPickedMedia(media);
      for (final file in others) {
        if (!mounted) return;
        await _sendFile(await file.readAsBytes(), name: file.name);
      }
    } finally {
      await discardSharedCopies(copies);
    }
  }

  Future<void> _sendMixedMediaBatch(List<XFile> picked) async {
    final items = <PickedMedia>[
      for (final file in picked)
        if (looksLikeVideo(file))
          PickedVideo(path: file.path, name: file.name)
        else
          PickedImage(bytes: await file.readAsBytes(), name: file.name),
    ];
    if (!mounted) return;

    final composed = await Navigator.of(context).push<List<ComposedMedia>>(
      MaterialPageRoute(builder: (_) => MediaCaptionComposerPage(items: items)),
    );
    if (composed == null) return;

    final groupId = composed.length > 1 ? _newGalleryGroupId() : null;
    await _keepingUploadAlive(() async {
      for (var i = 0; i < composed.length; i++) {
        if (!mounted) return;
        final gallery = groupId == null
            ? null
            : GalleryGroupRef(id: groupId, index: i, count: composed.length);
        switch (composed[i]) {
          case ComposedImageResult(:final image):
            await _sendPhoto(
              image.bytes,
              caption: image.caption,
              gallery: gallery,
            );
          case ComposedVideoResult(:final video):
            await _sendVideoAttachment(video, gallery: gallery);
        }
      }
    });
  }

  Future<void> _pickAndSendFile() async {
    final files = await FilePicker.pickFiles();
    final picked = files.singleOrNull;
    if (picked == null) return;
    await _sendFile(await picked.readAsBytes(), name: picked.name);
  }

  Future<void> _pickAndSendVideo(ImageSource source) async {
    final picked = await ImagePicker().pickVideo(source: source);
    if (picked == null || !mounted) return;
    await _pickAndSendVideoFile(picked);
  }

  Future<void> _pickAndSendVideoFile(XFile picked) async {
    final composed = await Navigator.of(context).push<ComposedVideo>(
      MaterialPageRoute(
        builder: (_) =>
            VideoCaptionComposerPage(path: picked.path, name: picked.name),
      ),
    );
    if (composed == null || !mounted) return;

    await _sendVideoAttachment(composed);
  }

  Future<void> _sendVideoAttachment(
    ComposedVideo composed, {
    GalleryGroupRef? gallery,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final txid = widget.room.client.generateUniqueTransactionId();
    return _guardedSend(
      txid,
      () => _withSendProgress(
        PendingAttachmentSend(
          eventId: txid,
          width: composed.width,
          height: composed.height,
          kind: SendMediaKind.video,
        ),
        (progress) async {
          final prepared = await prepareVideoForSend(
            composed.path,
            reduceMediaSize: ref.read(reduceMediaSizeProvider),
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
          await widget.room.sendFileEvent(
            prepared.file,
            txid: txid,
            thumbnail: prepared.thumbnail,
            extraContent: _attachmentExtraContent(
              caption: composed.caption,
              gallery: gallery,
            ),
          );
        },
      ),
      onFailed: (error) => _recordFailedSend(
        FailedMediaSend(
          gallery: gallery,
          video: composed,
          caption: composed.caption,
        ),
        error: error,
        messenger: messenger,
      ),
    );
  }

  Future<void> _sendPhoto(
    Uint8List bytes, {
    String? caption,
    GalleryGroupRef? gallery,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final txid = widget.room.client.generateUniqueTransactionId();
    return _guardedSend(
      txid,
      () => _withSendProgress(
        PendingAttachmentSend(
          eventId: txid,
          previewBytes: bytes,
          kind: SendMediaKind.photo,
        ),
        (progress) async {
          final prepared = await prepareImageForSend(
            bytes,
            reduceMediaSize: ref.read(reduceMediaSizeProvider),
            onProgress: progress.compression,
          );
          await widget.room.sendFileEvent(
            prepared.file,
            txid: txid,
            thumbnail: prepared.thumbnail,
            extraContent: _attachmentExtraContent(
              caption: caption,
              gallery: gallery,
            ),
          );
        },
      ),
      onFailed: (error) => _recordFailedSend(
        FailedMediaSend(gallery: gallery, bytes: bytes, caption: caption),
        error: error,
        messenger: messenger,
      ),
    );
  }

  Future<void> _sendFile(Uint8List bytes, {required String name}) {
    final messenger = ScaffoldMessenger.of(context);
    final txid = widget.room.client.generateUniqueTransactionId();
    return _guardedSend(
      txid,
      () => _withSendProgress(
        PendingAttachmentSend(eventId: txid, kind: SendMediaKind.file),
        (_) => widget.room.sendFileEvent(
          MatrixFile.fromMimeType(bytes: bytes, name: name),
          txid: txid,
          extraContent: _attachmentExtraContent(caption: null, gallery: null),
        ),
      ),
      onFailed: (error) => messenger.showSnackBar(
        const SnackBar(content: Text('Not sent. Try again.')),
      ),
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

  void _recordFailedSend(
    FailedMediaSend failed, {
    required Object error,
    required ScaffoldMessengerState messenger,
  }) {
    if (failed.gallery == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Not sent. Try again.')),
      );
    }
    if (!mounted) return;
    setState(() => _failedSends.add(failed));
  }

  Future<void> _retryFailedSend(FailedMediaSend failed) async {
    setState(() => _failedSends.remove(failed));
    switch (failed) {
      case FailedMediaSend(video: final video?):
        await _sendVideoAttachment(video, gallery: failed.gallery);
      case FailedMediaSend(bytes: final bytes?):
        await _sendPhoto(
          bytes,
          caption: failed.caption,
          gallery: failed.gallery,
        );
      default:
        return;
    }
  }

  Future<void> _resend(Event event) =>
      runBestEffort(event.sendAgain, label: 'sendAgain ${event.eventId}');

  void _retryAfterReconnect() {
    _markLatestRead();
    for (final failed in List<FailedMediaSend>.of(_failedSends)) {
      unawaited(_retryFailedSend(failed));
    }
    for (final event in notSentOwnEvents(_timeline?.events ?? const [])) {
      unawaited(_resend(event));
    }
  }

  Future<void> _showAttachmentMenu() async {
    final choice = await showModalBottomSheet<_Attachment>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.of(context).pop(_Attachment.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(context).pop(_Attachment.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Record video'),
              onTap: () => Navigator.of(context).pop(_Attachment.videoCamera),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_outlined),
              title: const Text('Choose file'),
              onTap: () => Navigator.of(context).pop(_Attachment.file),
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('Location'),
              onTap: () => Navigator.of(context).pop(_Attachment.location),
            ),
          ],
        ),
      ),
    );
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
      case null:
        break;
    }
  }

  Future<void> _sendLocation() async {
    final geo = await showLocationShareSheet(context);
    if (geo == null || !mounted) return;
    try {
      await widget.room.sendEvent(
        locationMessageContent(geo, timestamp: DateTime.now()),
      );
    } catch (_) {
      if (mounted) _snack('Location not sent. Try again.');
    }
  }

  static const _slideToCancelThreshold = 80.0;

  bool get _recordingWillCancel =>
      _recordingSlideOffset < -_slideToCancelThreshold;

  Duration get _elapsedRecordingDuration {
    final startedAt = _recordingStartedAt;
    return startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt);
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          _snack('Allow microphone access to record voice messages');
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = p.join(
        dir.path,
        'voice-${DateTime.now().millisecondsSinceEpoch}.ogg',
      );
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.opus),
        path: path,
      );
      if (!mounted) return;
      _waveformSamples.clear();
      _recordingStartedAt = DateTime.now();
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
    } catch (e) {
      logCaught('start recording', e);
      _tapToggleRecording = false;
      _micHeld = false;
      if (mounted) {
        setState(() {});
        _snack('Recording did not start. Try again.');
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
    final bytes = await file.readAsBytes();
    await file.delete();
    if (duration < const Duration(milliseconds: 100)) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.room.sendFileEvent(
        MatrixFile(
          bytes: bytes,
          name: 'Voice message.ogg',
          mimeType: 'audio/ogg',
        ),
        extraContent: {
          'org.matrix.msc3245.voice': {},
          'org.matrix.msc1767.audio': {
            'duration': duration.inMilliseconds,
            'waveform': waveform,
          },
        },
      );
    } catch (e) {
      logCaught('send voice message', e);
      messenger.showSnackBar(
        const SnackBar(content: Text('Voice message not sent. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final incognitoKeyboard = ref.watch(incognitoKeyboardProvider);
    final linkPreviewsEnabled = ref.watch(linkPreviewsEnabledProvider);
    final showHiddenMessages = ref.watch(showHiddenMessagesProvider);
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

    final inviteDisplay = roomInviteDisplay(widget.room);
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
            child: Text(widget.room.isDirectChat ? 'Chat info' : 'Room info'),
          ),
          if (!widget.room.isDirectChat && widget.room.canInvite)
            PopupMenuItem(
              onTap: () => unawaited(_addMembers()),
              child: const Text('Add members'),
            ),
          PopupMenuItem(
            onTap: () => unawaited(_addToHomeScreen()),
            child: const Text('Add to home screen'),
          ),
          PopupMenuItem(
            onTap: () => unawaited(_reinitializeConversation()),
            child: const Text('Reload messages'),
          ),
          PopupMenuItem(
            onTap: () async {
              if (!await confirmAndExitRoom(context, widget.room)) return;
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(roomExitLabel(widget.room)),
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
                  if (showActiveCallBanner)
                    _ActiveCallBanner(
                      call: activeRoomCall,
                      onJoin: () => _joinActiveCall(activeRoomCall),
                    ),
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
                                linkPreviews: linkPreviewsEnabled,
                                canReply: canPost,
                                failedSends: _failedSends,
                                pendingSend: _pendingSend,
                                replyTargets: _replyTargets,
                                onLongPress: (event, gallery) =>
                                    _showMessageActions(
                                      event,
                                      galleryEvents: gallery,
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
                  if (timeline != null &&
                      (_editingEvent != null || _replyingToEvent != null))
                    ComposeBar(
                      title: _editingEvent != null
                          ? 'Editing message'
                          : 'Replying to ${_replyingToEvent!.senderFromMemoryOrFallback.calcDisplayname()}',
                      snippet: previewSnippet(
                        _editingEvent ?? _replyingToEvent!,
                        timeline,
                      ),
                      onCancel: _cancelCompose,
                    ),
                  if (!widget.room.isDirectChat && canPost)
                    MentionSuggestions(room: widget.room, controller: _input),
                  if (canPost)
                    MessageComposer(
                      controller: _input,
                      onSend: _send,
                      onAttach: _showAttachmentMenu,
                      incognitoKeyboard: incognitoKeyboard,
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
                              ? '${inviteDisplay.title} left this chat'
                              : 'You cannot send messages here',
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
                  isVideo ? 'Video call in progress' : 'Voice call in progress',
                  style: TextStyle(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              FilledButton.tonal(onPressed: onJoin, child: const Text('Join')),
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
    return MessageFact(
      icon: seen.isEmpty ? Icons.done : Icons.done_all,
      child: Text(
        seen.isEmpty
            ? 'Not seen yet'
            : 'Seen by ${seen.map((s) => '${s.user.calcDisplayname()} · ${_formatDateTime(s.at)}').join('\n')}',
      ),
    );
  }
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
          message: 'Scroll to latest',
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
