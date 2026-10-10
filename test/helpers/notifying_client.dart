import 'package:matrix/matrix.dart';

import 'fake_matrix.dart';

PushruleEvaluator notifyOnMessagesEvaluator() => PushruleEvaluator.fromRuleset(
  PushRuleSet(
    underride: [
      PushRule(
        ruleId: '.m.rule.message',
        default$: true,
        enabled: true,
        conditions: [
          PushCondition(
            kind: 'event_match',
            key: 'type',
            pattern: 'm.room.message',
          ),
        ],
        actions: ['notify'],
      ),
    ],
  ),
);

class NotifyingClient extends Client {
  NotifyingClient() : super('test', database: FakeDatabaseApi());

  @override
  String? prevBatch = 's1';

  @override
  PushruleEvaluator get pushruleEvaluator => notifyOnMessagesEvaluator();
}
