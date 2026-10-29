import 'dart:io';

import '../brand.dart';

const _osDisplayNames = {'ios': 'iOS', 'macos': 'macOS'};

String sessionDisplayName(String operatingSystem) {
  if (operatingSystem.isEmpty) return '$zunoName on Unknown';
  final os =
      _osDisplayNames[operatingSystem] ??
      operatingSystem[0].toUpperCase() + operatingSystem.substring(1);
  return '$zunoName on $os';
}

String thisSessionDisplayName() => sessionDisplayName(Platform.operatingSystem);
