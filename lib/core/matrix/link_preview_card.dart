import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

import 'attachment_cache.dart';
import 'bearer_authorization.dart';
import 'connectivity_provider.dart';

class _PreviewCache {
  static const _ttl = Duration(hours: 1);
  static const _maxEntries = 64;
  static final _entries = <String, ({DateTime storedAt, PreviewForUrl? value})>{};

  static ({DateTime storedAt, PreviewForUrl? value})? _live(Uri url) {
    final key = url.toString();
    final entry = _entries[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.storedAt) > _ttl) {
      _entries.remove(key);
      return null;
    }
    return entry;
  }

  static PreviewForUrl? get(Uri url) => _live(url)?.value;

  static bool has(Uri url) => _live(url) != null;

  static void put(Uri url, PreviewForUrl? value) {
    final key = url.toString();
    _entries.remove(key);
    _entries[key] = (storedAt: DateTime.now(), value: value);
    if (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  static void clear() => _entries.clear();
}

void debugClearLinkPreviewCache() => _PreviewCache.clear();

class LinkPreviewCard extends ConsumerStatefulWidget {
  final Uri url;
  final Client client;

  const LinkPreviewCard({required this.url, required this.client, super.key});

  @override
  ConsumerState<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends ConsumerState<LinkPreviewCard> {
  Future<PreviewForUrl?>? _preview;

  Uri get url => widget.url;
  Client get client => widget.client;

  @override
  void initState() {
    super.initState();
    _preview = _load();
  }

  @override
  void didUpdateWidget(covariant LinkPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _preview = _load();
  }

  Future<PreviewForUrl?> _load() async {
    if (_PreviewCache.has(url)) return _PreviewCache.get(url);
    try {
      final preview = await client.getUrlPreview(url);
      _PreviewCache.put(url, preview);
      return preview;
    } catch (_) {
      _PreviewCache.put(url, null);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.read(isOfflineProvider).value ?? false) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<PreviewForUrl?>(
      future: _preview,
      builder: (context, snapshot) {
        final preview = snapshot.data;
        if (preview == null) return const SizedBox.shrink();

        final title = preview.additionalProperties.tryGet<String>('og:title');
        final description = preview.additionalProperties.tryGet<String>(
          'og:description',
        );
        final siteName = preview.additionalProperties.tryGet<String>(
          'og:site_name',
        );
        final image = preview.ogImage;
        if (title == null && description == null && image == null) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => launchUrl(url, mode: LaunchMode.externalApplication),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (image != null)
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: _LinkPreviewImage(client: client, mxcUri: image),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (title != null)
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          if (description != null)
                            Text(
                              description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (siteName != null)
                            Text(
                              siteName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LinkPreviewImage extends StatelessWidget {
  final Client client;
  final Uri mxcUri;

  const _LinkPreviewImage({required this.client, required this.mxcUri});

  Future<Uint8List> _fetch() async {
    final uri = await mxcUri.getThumbnailUri(client, width: 144, height: 144);
    return fetchCachedAttachment('linkpreview:$uri', () async {
      final response = await client.httpClient.get(
        uri,
        headers: {'authorization': await bearerAuthorization(client)},
      );
      if (response.statusCode != 200) {
        throw Exception(
          'Link preview image fetch failed: HTTP ${response.statusCode}',
        );
      }
      return response.bodyBytes;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _fetch(),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          );
        }
        return Image.memory(bytes, fit: BoxFit.cover);
      },
    );
  }
}
