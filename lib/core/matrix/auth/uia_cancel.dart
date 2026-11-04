bool isUiaCancel(Object error) =>
    error is Exception && '$error' == 'Exception: Request has been canceled';

class UnanswerableUiaStages implements Exception {
  const UnanswerableUiaStages(this.stages);

  final Set<String> stages;

  @override
  String toString() => 'UnanswerableUiaStages(${stages.join(', ')})';
}
