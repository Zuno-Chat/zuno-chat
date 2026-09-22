import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'attachment_cache.dart';

class CachedAttachmentImage extends StatelessWidget {
  final Event event;
  final bool thumbnail;
  final Widget placeholder;
  final Widget Function(BuildContext context, Uint8List bytes) builder;

  const CachedAttachmentImage({
    required this.event,
    required this.thumbnail,
    required this.placeholder,
    required this.builder,
    super.key,
  });

  String get _cacheKey => attachmentCacheKey(event, thumbnail: thumbnail);

  Future<Uint8List> _fetch() => fetchCachedAttachment(_cacheKey, () async {
    final file = await event.downloadAndDecryptAttachment(
      getThumbnail: thumbnail,
    );
    return file.bytes;
  });

  @override
  Widget build(BuildContext context) {
    final cached = AttachmentCache.instance.get(_cacheKey);
    if (cached != null) return builder(context, cached);

    return FutureBuilder<Uint8List>(
      future: _fetch(),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return placeholder;
        return builder(context, bytes);
      },
    );
  }
}
