String formatSessionKey(String key) {
  final groups = <String>[];
  for (var i = 0; i < key.length; i += 4) {
    final end = i + 4 > key.length ? key.length : i + 4;
    groups.add(key.substring(i, end));
  }
  return groups.join(' ');
}
