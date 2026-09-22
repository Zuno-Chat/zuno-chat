enum MetaStatus { none, sending, sent, read }

enum RunPosition {
  single,
  first,
  middle,
  last;

  static RunPosition of({required bool startsRun, required bool endsRun}) {
    if (startsRun) return endsRun ? single : first;
    return endsRun ? last : middle;
  }
}
