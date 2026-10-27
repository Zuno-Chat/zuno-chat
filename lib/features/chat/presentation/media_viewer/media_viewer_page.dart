import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../../core/errors/best_effort.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/matrix/attachment_feedback.dart';
import '../../../../core/matrix/media_audio_session.dart';
import '../../../../core/matrix/reactions.dart';
import '../../../../core/matrix/room_media_feed.dart';
import '../../../../core/matrix/room_permission.dart';
import '../../../../core/ui/close_own_route.dart';
import '../../../../core/ui/sheet.dart';
import '../../../../core/ui/system_bars.dart';
import '../../../../core/ui/zuno_colors.dart';
import '../../../../core/ui/zuno_motion.dart';
import '../../../../core/ui/zuno_theme.dart';
import '../../data/viewer_items.dart';
import '../message_actions.dart';
import '../message_actions_sheet.dart';
import 'media_hero.dart';
import 'video_playback.dart';
import 'viewer_chrome.dart';
import 'viewer_dismiss.dart';
import 'viewer_photo.dart';
import 'viewer_video.dart';

const _autoHideAfter = Duration(seconds: 3);
const _loadOlderWithin = 3;

class ViewerChat {
  final Room room;
  final ValueListenable<Timeline?> timeline;
  final void Function(Event event) startReply;
  final void Function(Event event) startEdit;

  const ViewerChat({
    required this.room,
    required this.timeline,
    required this.startReply,
    required this.startEdit,
  });
}

Future<void> openMediaViewer(
  BuildContext context, {
  required ViewerChat chat,
  required Event opened,
}) {
  final route = ModalRoute.of(context);
  return Navigator.of(context).push(
    MediaViewerRoute(
      builder: (_) => MediaViewerPage(
        chat: chat,
        opened: opened,
        heroTag: route == null ? null : mediaHeroTag(route, opened),
      ),
    ),
  );
}

class MediaViewerPage extends ConsumerStatefulWidget {
  final ViewerChat chat;
  final Event opened;
  final Object? heroTag;

  const MediaViewerPage({
    required this.chat,
    required this.opened,
    required this.heroTag,
    super.key,
  });

  @override
  ConsumerState<MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends ConsumerState<MediaViewerPage> {
  late final ViewerItems _items;
  late final PageController _pages;
  late List<Event> _list;
  late Map<String, int> _positions;
  late int _index;
  final _playbacks = <String, VideoPlayback>{};
  late Event _target;
  final _fetchedReactions = <String, List<Event>>{};
  final _fetchingReactions = <String>{};
  final _refetchReactions = <String>{};
  final _dismissProgress = ValueNotifier<double>(0);
  bool _chromeVisible = true;
  bool _dragging = false;
  String? _zoomedId;
  bool _muted = false;
  bool _scrolling = false;
  bool _itemsChangedWhileScrolling = false;
  bool _loadingScheduled = false;
  bool _left = false;
  Timer? _autoHide;

  Event get _shown => _list[_index];

  bool get _zoomed => _zoomedId == _shown.eventId;

  @override
  void initState() {
    super.initState();
    _items = ViewerItems(
      ref.read(roomMediaFeedProvider(widget.chat.room)),
      opened: widget.opened,
    );
    _show(_items.items.isEmpty ? [widget.opened] : _items.items);
    _index = math.max(0, _positions[widget.opened.eventId] ?? 0);
    _pages = PageController(initialPage: _index);
    _items.addListener(_onItemsChanged);
    widget.chat.timeline.addListener(_ensureReactions);
    _retarget();
    if (_isVideo(widget.opened)) _play(widget.opened);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadingScheduled) return;
    _loadingScheduled = true;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) {
      _startLoading();
      return;
    }
    void onStatus(AnimationStatus status) {
      if (!status.isCompleted) return;
      animation.removeStatusListener(onStatus);
      if (mounted) _startLoading();
    }

    animation.addStatusListener(onStatus);
  }

  @override
  void dispose() {
    _autoHide?.cancel();
    widget.chat.timeline.removeListener(_ensureReactions);
    _items
      ..removeListener(_onItemsChanged)
      ..dispose();
    for (final playback in _playbacks.values) {
      playback.dispose();
    }
    _pages.dispose();
    _dismissProgress.dispose();
    if (!_left) unawaited(showSystemBars());
    super.dispose();
  }

  static bool _isVideo(Event event) => event.messageType == MessageTypes.Video;

  void _show(List<Event> list) {
    _list = list;
    _positions = {
      for (final (index, event) in list.indexed) event.eventId: index,
    };
  }

  void _startLoading() {
    _items.start();
    _loadOlderIfNear();
  }

  void _onItemsChanged() {
    if (_scrolling) {
      _itemsChangedWhileScrolling = true;
      return;
    }
    _applyItems();
  }

  void _applyItems() {
    _itemsChangedWhileScrolling = false;
    final items = _items.items;
    if (identical(items, _list)) {
      _loadOlderIfNear();
      return;
    }
    if (items.isEmpty) {
      closeOwnRouteAndAbove(context);
      return;
    }
    final previous = _shown.eventId;
    final kept = items.indexWhere((e) => e.eventId == previous);
    final index = kept == -1 ? _index.clamp(0, items.length - 1) : kept;
    if (index != _index && _pages.hasClients) {
      final position = _pages.position;
      position.correctPixels(index * position.viewportDimension);
    }
    setState(() {
      _show(items);
      _index = index;
    });
    _retarget();
    if (_shown.eventId != previous) _settleOn(index);
    _loadOlderIfNear();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      _scrolling = true;
    } else if (notification is ScrollEndNotification) {
      _scrolling = false;
      if (_itemsChangedWhileScrolling) _applyItems();
      if (_index == 0 && !_items.canLoadOlder) {
        unawaited(_items.retryOlder());
      }
    }
    return false;
  }

  void _loadOlderIfNear() {
    if (_index < _loadOlderWithin) unawaited(_items.loadOlder());
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    _retarget();
    _settleOn(index);
    _loadOlderIfNear();
  }

  void _settleOn(int index) {
    final keep = {
      for (var i = index - 1; i <= index + 1; i++)
        if (i >= 0 && i < _list.length) _list[i].eventId,
    };
    _playbacks.removeWhere((id, playback) {
      if (id != _shown.eventId) unawaited(playback.pause());
      if (keep.contains(id)) return false;
      playback.dispose();
      return true;
    });
    _restartAutoHide();
  }

  void _play(Event event) {
    final playback = _playbacks.putIfAbsent(
      event.eventId,
      () => VideoPlayback(
        event,
        muted: _muted,
        audio: ref.read(mediaAudioSessionProvider),
      )..addListener(_scheduleAutoHide),
    );
    unawaited(playback.start());
    if (mounted) setState(() {});
  }

  void _scheduleAutoHide() {
    final playing = _playbacks[_shown.eventId]?.playing ?? false;
    if (_left || !playing || !_chromeVisible) {
      _autoHide?.cancel();
      _autoHide = null;
      return;
    }
    _autoHide ??= Timer(_autoHideAfter, () {
      _autoHide = null;
      if (mounted) _showChrome(false);
    });
  }

  void _restartAutoHide() {
    _autoHide?.cancel();
    _autoHide = null;
    _scheduleAutoHide();
  }

  void _showChrome(bool visible) {
    setState(() => _chromeVisible = visible);
    unawaited(visible ? showSystemBars() : hideSystemBars());
    _restartAutoHide();
  }

  void _toggleChrome() => _showChrome(!_chromeVisible);

  void _toggleMute() {
    setState(() => _muted = !_muted);
    for (final playback in _playbacks.values) {
      playback.muted = _muted;
    }
  }

  void _onZoomChanged(Event event, bool zoomed) {
    setState(() {
      if (zoomed) {
        _zoomedId = event.eventId;
      } else if (_zoomedId == event.eventId) {
        _zoomedId = null;
      }
    });
  }

  void _onDismissProgress(double progress) {
    _dismissProgress.value = progress;
    final dragging = progress > 0;
    if (dragging == _dragging) return;
    setState(() => _dragging = dragging);
    final route = ModalRoute.of(context);
    if (route is MediaViewerRoute) route.revealRouteBelow(dragging);
  }

  void _leave() {
    if (_left) return;
    _left = true;
    _autoHide?.cancel();
    _autoHide = null;
    for (final playback in _playbacks.values) {
      unawaited(playback.pause());
    }
    unawaited(showSystemBars());
  }

  Timeline? get _timeline => widget.chat.timeline.value;

  void _retarget() {
    _target = _items.galleryOf(_shown)?.message ?? _shown;
    _ensureReactions();
  }

  void _ensureReactions({bool refresh = false}) {
    final timeline = _timeline;
    final target = _target;
    final id = target.eventId;
    if (timeline == null || timeline.events.any((e) => e.eventId == id)) {
      return;
    }
    if (_fetchingReactions.contains(id)) {
      if (refresh) _refetchReactions.add(id);
      return;
    }
    if (!refresh && _fetchedReactions.containsKey(id)) return;
    _fetchingReactions.add(id);
    unawaited(_fetchReactions(target));
  }

  Future<void> _fetchReactions(Event target) async {
    await runBestEffort(() async {
      final fetched = await fetchReactions(target);
      if (mounted) setState(() => _fetchedReactions[target.eventId] = fetched);
    }, label: 'viewer reactions');
    _fetchingReactions.remove(target.eventId);
    if (_refetchReactions.remove(target.eventId) && mounted) {
      _fetchingReactions.add(target.eventId);
      unawaited(_fetchReactions(target));
    }
  }

  void _afterReacting(Event target) {
    if (mounted && identical(target, _target)) _ensureReactions(refresh: true);
  }

  Future<void> _toggleReaction(String key) async {
    final timeline = _timeline;
    if (timeline == null) return;
    final target = _target;
    await reactToMessage(context, target, timeline, key);
    _afterReacting(target);
  }

  Future<void> _pickReaction() async {
    final timeline = _timeline;
    if (timeline == null) return;
    final target = _target;
    await pickReaction(context, target, timeline);
    _afterReacting(target);
  }

  Future<void> _react() async {
    await showSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
          child: QuickReactionRow(
            onReact: (emoji) {
              Navigator.of(sheetContext).pop();
              unawaited(_toggleReaction(emoji));
            },
            onMore: () {
              Navigator.of(sheetContext).pop();
              unawaited(_pickReaction());
            },
          ),
        ),
      ),
    );
  }

  Future<void> _more() async {
    final timeline = _timeline;
    if (timeline == null) return;
    final gallery = _items.galleryOf(_shown);
    await showMessageActions(
      context,
      ref,
      room: widget.chat.room,
      timeline: timeline,
      event: gallery?.message ?? _shown,
      gallery: gallery?.members,
      onReply: widget.chat.startReply,
      onEdit: widget.chat.startEdit,
    );
  }

  Widget _page(BuildContext context, int index) {
    final event = _list[index];
    final heroTag = index == _index && event.eventId == widget.opened.eventId
        ? widget.heroTag
        : null;
    final Widget media = _isVideo(event)
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleChrome,
            child: ViewerVideo(
              event: event,
              heroTag: heroTag,
              playback: _playbacks[event.eventId],
              controlsVisible: _chromeVisible,
              onPlay: () => _play(event),
            ),
          )
        : ViewerPhoto(
            event: event,
            heroTag: heroTag,
            onTap: _toggleChrome,
            onZoomChanged: (zoomed) => _onZoomChanged(event, zoomed),
          );
    return KeyedSubtree(key: ValueKey(event.eventId), child: media);
  }

  @override
  Widget build(BuildContext context) {
    final item = _shown;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _leave();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Theme(
          data: zunoViewerTheme,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: BackdropGroup(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ValueListenableBuilder(
                      valueListenable: _dismissProgress,
                      builder: (context, progress, _) => ColoredBox(
                        color: mediaBackdropColor.withValues(
                          alpha: 1 - progress,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: ViewerDismiss(
                      enabled: !_zoomed,
                      onProgress: _onDismissProgress,
                      onDismiss: () => closeOwnRouteAndAbove(context),
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _onScroll,
                        child: PageView.builder(
                          controller: _pages,
                          physics: _zoomed
                              ? const NeverScrollableScrollPhysics()
                              : const AlwaysScrollableScrollPhysics(),
                          itemCount: _list.length,
                          onPageChanged: _onPageChanged,
                          findChildIndexCallback: (key) =>
                              _positions[(key as ValueKey<String>).value],
                          itemBuilder: _page,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: ListenableBuilder(
                      listenable: widget.chat.timeline,
                      builder: (context, _) {
                        final timeline = _timeline;
                        final canRespond =
                            timeline != null &&
                            canRespondTo(widget.chat.room, item);
                        return ViewerChrome(
                          event: item,
                          visible: _chromeVisible && !_dragging,
                          playback: _playbacks[item.eventId],
                          muted: _muted,
                          onInteraction: _restartAutoHide,
                          onBack: () => Navigator.of(context).maybePop(),
                          onShare: () => shareAttachmentsWithFeedback(
                            messenger,
                            l10n,
                            [item],
                          ),
                          onSave: () => saveAttachmentsWithFeedback(
                            messenger,
                            l10n,
                            [item],
                          ),
                          onToggleMute: _toggleMute,
                          onMore: timeline == null ? null : _more,
                          onReact: canRespond ? _react : null,
                          onReply: canRespond
                              ? () => widget.chat.startReply(item)
                              : null,
                          reactions: timeline == null
                              ? const []
                              : reactionSummaries(
                                  _target,
                                  timeline,
                                  fetched:
                                      _fetchedReactions[_target.eventId] ??
                                      const [],
                                ),
                          onToggleReaction: canRespond
                              ? (key) => unawaited(_toggleReaction(key))
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
