const _appDisplayName = 'Zuno';

const _osDisplayNames = {'ios': 'iOS', 'macos': 'macOS'};

String sessionDisplayName(String operatingSystem) {
  if (operatingSystem.isEmpty) return '$_appDisplayName on Unknown';
  final os =
      _osDisplayNames[operatingSystem] ??
      operatingSystem[0].toUpperCase() + operatingSystem.substring(1);
  return '$_appDisplayName on $os';
}
