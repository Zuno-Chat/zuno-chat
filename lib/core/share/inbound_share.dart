import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart' show MatrixFile, MessageTypes;
import 'package:mime/mime.dart';

import '../errors/caught_errors.dart';
import '../files/file_system.dart';
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

const _unknownType = 'application/octet-stream';

Future<String> _sharedFileType(XFile file) async {
  final declared = file.mimeType;
  if (declared != null && declared != _unknownType) return declared;
  return lookupMimeType(file.name, headerBytes: await _headerOf(file)) ??
      _unknownType;
}

Future<List<int>?> _headerOf(XFile file) async {
  final header = fileSystem
      .file(file.path)
      .openRead(0, defaultMagicNumbersMaxLength);
  try {
    return [await for (final chunk in header) ...chunk];
  } on FileSystemException {
    return null;
  }
}

Future<({List<XFile> media, List<XFile> others})> partitionSharedFiles(
  List<XFile> files,
) async {
  final media = <XFile>[];
  final others = <XFile>[];
  for (final file in files) {
    final type = await _sharedFileType(file);
    final typed = XFile(file.path, mimeType: type);
    final kind = MatrixFile.msgTypeFromMime(type);
    (kind == MessageTypes.Image || kind == MessageTypes.Video ? media : others)
        .add(typed);
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
  } on PlatformException catch (e, s) {
    reportCaught('copy shared files', e, s);
    return const [];
  } on MissingPluginException catch (e, s) {
    reportCaught('copy shared files', e, s);
    return const [];
  }
  if (paths == null) return const [];
  return [
    for (var i = 0; i < files.length && i < paths.length; i++)
      if (paths[i] case final path?)
        XFile(path, name: files[i].name, mimeType: files[i].mimeType),
  ];
}
