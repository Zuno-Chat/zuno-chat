String? roomNameError(String name) {
  final normalized = name.toLowerCase().replaceAll('0', 'o');
  if (normalized.contains('zuno')) return 'Names cannot include Zuno';
  return null;
}
