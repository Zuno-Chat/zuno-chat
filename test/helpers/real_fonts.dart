import 'dart:io';

import 'package:flutter/services.dart';

Future<void> loadRealRoboto() async {
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final dir = Directory('${artifacts.path}/material_fonts');
  if (!dir.existsSync()) {
    throw StateError('No material_fonts in the Flutter cache: ${dir.path}');
  }
  final roboto = FontLoader('Roboto');
  for (final name in [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    final bytes = File('${dir.path}/$name').readAsBytesSync();
    roboto.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await roboto.load();
}
