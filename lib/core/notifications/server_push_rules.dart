import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../matrix/matrix_client_provider.dart';

typedef SilentRelationRule = ({String ruleId, String relType});

const encryptedReactionRule = (
  ruleId: 'im.zuno.encrypted_reaction',
  relType: 'm.annotation',
);

const referenceRule = (
  ruleId: 'im.zuno.reference',
  relType: RelationshipTypes.reference,
);

const silentRelationRules = [encryptedReactionRule, referenceRule];

const _relationTypeKey = r'content.m\.relates_to.rel_type';
const _messageRuleId = '.m.rule.message';
const _soundTweak = {'set_tweak': 'sound', 'value': 'default'};

bool silentRelationRuleIsCurrent(
  PushRuleSet? rules,
  SilentRelationRule wanted,
) {
  final override = rules?.override ?? const <PushRule>[];
  final rule = override.where((r) => r.ruleId == wanted.ruleId).firstOrNull;
  if (rule == null || !rule.enabled || rule.actions.isNotEmpty) return false;
  final conditions = rule.conditions;
  if (conditions == null || conditions.length != 1) return false;
  final condition = conditions.single;
  return condition.kind == 'event_property_is' &&
      condition.key == _relationTypeKey &&
      condition.value == wanted.relType;
}

Future<void> ensureSilentRelationRule(
  Client client,
  SilentRelationRule rule,
) async {
  final rules = client.globalPushRules;
  if (rules == null || silentRelationRuleIsCurrent(rules, rule)) return;
  await client.setPushRule(
    PushRuleKind.override,
    rule.ruleId,
    const [],
    conditions: [
      PushCondition(
        kind: 'event_property_is',
        key: _relationTypeKey,
        value: rule.relType,
      ),
    ],
  );
}

PushRule? _messageRule(PushRuleSet? rules) =>
    rules?.underride?.where((r) => r.ruleId == _messageRuleId).firstOrNull;

bool messageRuleNeedsSound(PushRuleSet? rules) {
  final rule = _messageRule(rules);
  if (rule == null || !rule.enabled) return false;
  if (!rule.actions.contains('notify')) return false;
  return !rule.actions.any((a) => a is Map && a['set_tweak'] == 'sound');
}

Future<void> ensureMessageRuleSound(Client client) async {
  final rules = client.globalPushRules;
  if (!messageRuleNeedsSound(rules)) return;
  await client.setPushRuleActions(PushRuleKind.underride, _messageRuleId, [
    ..._messageRule(rules)!.actions,
    _soundTweak,
  ]);
}

final pushRuleMaintenanceProvider =
    NotifierProvider<PushRuleMaintenanceNotifier, void>(
      PushRuleMaintenanceNotifier.new,
    );

class PushRuleMaintenanceNotifier extends Notifier<void> {
  bool _done = false;
  bool _running = false;

  @override
  void build() {
    final client = ref.watch(matrixClientProvider);
    final sub = client.onSync.stream.listen((_) => _maintain(client));
    ref.onDispose(sub.cancel);
  }

  Future<void> _maintain(Client client) async {
    if (_done || _running || client.globalPushRules == null) return;
    _running = true;
    try {
      for (final rule in silentRelationRules) {
        await ensureSilentRelationRule(client, rule);
      }
      await ensureMessageRuleSound(client);
      _done = true;
    } catch (e) {
      debugPrint('zuno/push: could not maintain the push rules: $e');
    } finally {
      _running = false;
    }
  }
}
