String stripReplyFallback(String body) {
  if (!body.startsWith('> <')) return body;
  var result = '';
  var inPrefix = true;
  for (final line in body.split('\n')) {
    if (inPrefix && (line.isEmpty || line.startsWith('> '))) continue;
    inPrefix = false;
    result += result.isEmpty ? line : '\n$line';
  }
  return result;
}
