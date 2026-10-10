class NativeCaughtError implements Exception {
  const NativeCaughtError({
    required this.type,
    required this.message,
    this.domain,
    this.code,
    this.stack,
  });

  factory NativeCaughtError.fromMap(Map<Object?, Object?> entry) =>
      NativeCaughtError(
        type: _text(entry['type']) ?? 'unknown',
        message: _text(entry['message']) ?? '',
        domain: _text(entry['domain']),
        code: entry['code'] is int ? entry['code'] as int : null,
        stack: _text(entry['stack']),
      );

  static String? _text(Object? value) => value is String ? value : null;

  final String type;
  final String message;
  final String? domain;
  final int? code;
  final String? stack;

  @override
  String toString() {
    final origin = domain == null ? type : '$type ($domain $code)';
    final trace = stack == null || stack!.isEmpty ? '' : '\n$stack';
    return '$origin: $message$trace';
  }
}
