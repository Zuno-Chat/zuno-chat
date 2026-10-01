import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';

import '../errors/best_effort.dart';
import '../matrix/looks_like_video.dart';
import '../navigation/held_broadcast.dart';
import '../platform/platform_capabilities.dart';

const _channel = MethodChannel('zuno/share');

final _shares = HeldBroadcast<InboundShare>();

Stream<InboundShare> get onInboundShare => _shares.stream;

class SharedFile {
  final String uri;
  final String name;
  final String? mimeType;

  const SharedFile({required this.uri, required this.name, this.mimeType});

  static SharedFile? _fromChannel(Object? raw) {
    if (raw is! Map) return null;
    final uri = raw['uri'];
    final name = raw['name'];
    if (uri is! String || name is! String) return null;
    final mime = raw['mimeType'];
    return SharedFile(
      uri: uri,
      name: name,
      mimeType: mime is String && mime.isNotEmpty ? mime : null,
    );
  }
}

class InboundShare {
  final String? text;
  final List<SharedFile> files;

  const InboundShare({this.text, this.files = const []});

  static InboundShare? fromChannel(Object? raw) {
    if (raw is! Map) return null;
    final rawFiles = raw['files'];
    final files = <SharedFile>[
      if (rawFiles is List)
        for (final item in rawFiles) ?SharedFile._fromChannel(item),
    ];
    final text = raw['text'];
    final cleanText = text is String && text.trim().isNotEmpty ? text : null;
    if (cleanText == null && files.isEmpty) return null;
    return InboundShare(text: cleanText, files: files);
  }
}

bool isSharedMedia(XFile file) {
  final mime = file.mimeType;
  if (mime != null) {
    return mime.startsWith('image/') || mime.startsWith('video/');
  }
  return looksLikeVideo(file);
}

({List<XFile> media, List<XFile> others}) partitionSharedFiles(
  List<XFile> files,
) {
  final media = <XFile>[];
  final others = <XFile>[];
  for (final file in files) {
    (isSharedMedia(file) ? media : others).add(file);
  }
  return (media: media, others: others);
}

bool _receivesShares(PlatformCapabilities? capabilities) =>
    (capabilities ?? ambientCapabilities).inboundShare;

void initInboundShareChannel({PlatformCapabilities? capabilities}) {
  if (!_receivesShares(capabilities)) return;
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'share') {
      final share = InboundShare.fromChannel(call.arguments);
      if (share != null) _shares.add(share);
    }
    return null;
  });
}

Future<InboundShare?> takeLaunchShare({
  PlatformCapabilities? capabilities,
}) async {
  if (!_receivesShares(capabilities)) return null;
  return InboundShare.fromChannel(
    await _channel.invokeMethod<Object?>('takeLaunchShare'),
  );
}

Future<List<XFile>> copySharedFilesToCache(
  List<SharedFile> files, {
  PlatformCapabilities? capabilities,
}) async {
  if (files.isEmpty || !_receivesShares(capabilities)) return const [];
  final List<String?>? paths;
  try {
    paths = await _channel.invokeListMethod<String?>('copyToCache', {
      'uris': [for (final file in files) file.uri],
      'names': [for (final file in files) file.name],
    });
  } on PlatformException catch (e) {
    logCaught('copy shared files', e);
    return const [];
  } on MissingPluginException catch (e) {
    logCaught('copy shared files', e);
    return const [];
  }
  if (paths == null) return const [];
  return [
    for (var i = 0; i < files.length && i < paths.length; i++)
      if (paths[i] case final path?)
        XFile(path, name: files[i].name, mimeType: files[i].mimeType),
  ];
}

Future<void> discardSharedCopies(List<XFile> copies) async {
  for (final copy in copies) {
    try {
      await File(copy.path).delete();
    } on FileSystemException {
      continue;
    }
  }
}
