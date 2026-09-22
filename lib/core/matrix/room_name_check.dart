String? roomNameError(String name) {
  final normalized = name.toLowerCase().replaceAll('0', 'o');
  if (normalized.contains('zuno')) return 'Room names cannot include Zuno';
  return null;
}
