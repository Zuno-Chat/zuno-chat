final _osVersion = RegExp(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?');

List<int>? osVersionParts(String osVersion) {
  final match = _osVersion.firstMatch(osVersion);
  if (match == null) return null;
  return [
    for (var group = 1; group <= 3; group++)
      int.tryParse(match.group(group) ?? '0') ?? 0,
  ];
}

bool osAtLeast(String deviceVersion, String minimum) {
  final device = osVersionParts(deviceVersion);
  final needed = osVersionParts(minimum);
  if (device == null || needed == null) return false;
  for (var part = 0; part < 3; part++) {
    if (device[part] != needed[part]) return device[part] > needed[part];
  }
  return true;
}
