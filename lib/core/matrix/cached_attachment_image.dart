import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'attachment_actions.dart';
import 'attachment_cache.dart';
import 'blurhash_image.dart';

final class _Reconnects extends ChangeNotifier {
  void reconnected() => notifyListeners();
}

final _reconnects = _Reconnects();

void retryFailedAttachmentImages() => _reconnects.reconnected();

@visibleForTesting
Listenable get attachmentImageRetries => _reconnects;

class CachedAttachmentImage extends StatefulWidget {
  final Event event;
  final bool thumbnail;
  final ImageProvider Function(BuildContext context, ImageProvider attachment)?
  image;
  final BoxFit? fit;
  final Widget placeholder;
  final Widget? progress;
  final Widget Function(VoidCallback? retry)? failure;

  const CachedAttachmentImage({
    required this.event,
    required this.thumbnail,
    this.image,
    this.fit,
    this.placeholder = const SizedBox.shrink(),
    this.progress,
    this.failure,
    super.key,
  });

  @override
  State<CachedAttachmentImage> createState() => _CachedAttachmentImageState();
}

class _CachedAttachmentImageState extends State<CachedAttachmentImage> {
  var _attempt = 0;

  void _retry() => setState(() => _attempt++);

  Widget get _standIn {
    final blurhash = BlurhashImage.of(
      widget.event,
      thumbnail: widget.thumbnail,
    );
    if (blurhash == null) return widget.placeholder;
    return Image(
      image: blurhash,
      fit: widget.fit ?? BoxFit.cover,
      excludeFromSemantics: true,
    );
  }

  Widget get _waiting {
    final progress = widget.progress;
    if (progress == null) return _standIn;
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.passthrough,
      children: [
        _standIn,
        Center(child: progress),
      ],
    );
  }

  Widget _failed(Object error) {
    final retry = error is _DownloadFailed ? _retry : null;
    final shown = widget.failure?.call(retry) ?? _standIn;
    if (retry == null) return shown;
    return _RetryOnReconnect(retry: retry, child: shown);
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    if (widget.thumbnail &&
        event.messageType == MessageTypes.Video &&
        !event.hasThumbnail) {
      return _standIn;
    }
    final attachment = _AttachmentImage(event, thumbnail: widget.thumbnail);
    return Image(
      key: ValueKey(_attempt),
      image: widget.image?.call(context, attachment) ?? attachment,
      fit: widget.fit,
      frameBuilder: (context, child, frame, synchronous) =>
          frame == null && !synchronous ? _waiting : child,
      errorBuilder: (context, error, _) => _failed(error),
    );
  }
}

class _RetryOnReconnect extends StatefulWidget {
  final VoidCallback retry;
  final Widget child;

  const _RetryOnReconnect({required this.retry, required this.child});

  @override
  State<_RetryOnReconnect> createState() => _RetryOnReconnectState();
}

class _RetryOnReconnectState extends State<_RetryOnReconnect> {
  @override
  void initState() {
    super.initState();
    _reconnects.addListener(_retry);
  }

  @override
  void dispose() {
    _reconnects.removeListener(_retry);
    super.dispose();
  }

  void _retry() => widget.retry();

  @override
  Widget build(BuildContext context) => widget.child;
}

class _DownloadFailed implements Exception {
  final Object cause;

  const _DownloadFailed(this.cause);

  @override
  String toString() => 'attachment download failed: $cause';
}

class _AttachmentImage extends ImageProvider<(Type, String)> {
  final Event event;
  final bool thumbnail;

  const _AttachmentImage(this.event, {required this.thumbnail});

  String get _cacheKey => attachmentCacheKey(event, thumbnail: thumbnail);

  @override
  Future<(Type, String)> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture((_AttachmentImage, _cacheKey));

  @override
  ImageStreamCompleter loadImage(
    (Type, String) key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(key, decode),
    scale: 1,
    debugLabel: _cacheKey,
  );

  Future<ui.Codec> _load(
    (Type, String) key,
    ImageDecoderCallback decode,
  ) async {
    try {
      return await decode(
        await ui.ImmutableBuffer.fromUint8List(await _download()),
      );
    } catch (_) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }

  Future<Uint8List> _download() async {
    try {
      return await cachedAttachmentBytes(event, thumbnail: thumbnail);
    } catch (e) {
      throw _DownloadFailed(e);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is _AttachmentImage && other._cacheKey == _cacheKey;

  @override
  int get hashCode => _cacheKey.hashCode;
}
