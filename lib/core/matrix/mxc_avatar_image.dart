import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:matrix/matrix.dart';

import 'attachment_cache.dart';
import 'bearer_authorization.dart';

enum AvatarBucket {
  small(96, ThumbnailMethod.crop),
  large(320, ThumbnailMethod.scale);

  const AvatarBucket(this.pixels, this.method);

  final int pixels;
  final ThumbnailMethod method;

  static AvatarBucket forDiameter(double diameter) =>
      diameter <= 56 ? small : large;
}

class MxcAvatarImage extends ImageProvider<MxcAvatarImage> {
  final Client client;
  final Uri mxc;
  final AvatarBucket bucket;
  final DiskAttachmentCache? disk;

  const MxcAvatarImage({
    required this.client,
    required this.mxc,
    required this.bucket,
    this.disk,
  });

  String get _cacheKey => 'avatar:$mxc:${bucket.name}';

  @override
  Future<MxcAvatarImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    MxcAvatarImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: _cacheKey,
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    try {
      final bytes = await fetchCachedAvatar(_cacheKey, _download, disk: disk);
      try {
        return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
      } catch (_) {
        await (disk ?? DiskAttachmentCache.instance).remove(_cacheKey);
        rethrow;
      }
    } catch (_) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
      rethrow;
    }
  }

  Future<Uint8List> _download() async {
    final uri = await mxc.getThumbnailUri(
      client,
      width: bucket.pixels,
      height: bucket.pixels,
      method: bucket.method,
    );
    final response = await client.httpClient.get(
      uri,
      headers: {'authorization': await bearerAuthorization(client)},
    );
    if (response.statusCode != 200) {
      throw Exception('Avatar fetch failed: HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  @override
  bool operator ==(Object other) =>
      other is MxcAvatarImage && other.mxc == mxc && other.bucket == bucket;

  @override
  int get hashCode => Object.hash(mxc, bucket);
}
