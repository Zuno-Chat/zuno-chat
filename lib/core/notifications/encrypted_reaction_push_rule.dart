import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../matrix/matrix_client_provider.dart';

const encryptedReactionRuleId = 'im.zuno.encrypted_reaction';

const _relationTypeKey = r'content.m\.relates_to.rel_type';
const _annotation = 'm.annotation';

bool encryptedReactionRuleIsCurrent(PushRuleSet? rules) {
  final override = rules?.override ?? const <PushRule>[];
  final matches = override.where((r) => r.ruleId == encryptedReactionRuleId);
  if (matches.isEmpty) return false;
  final rule = matches.first;
  if (!rule.enabled) return false;
  if (rule.actions.isNotEmpty) return false;
  final conditions = rule.conditions;
  if (conditions == null || conditions.length != 1) return false;
  final condition = conditions.single;
  return condition.kind == 'event_property_is' &&
      condition.key == _relationTypeKey &&
      condition.value == _annotation;
}

Future<void> ensureEncryptedReactionPushRule(Client client) async {
  final rules = client.globalPushRules;
  if (rules == null || encryptedReactionRuleIsCurrent(rules)) return;
  await client.setPushRule(
    PushRuleKind.override,
    encryptedReactionRuleId,
    const [],
    conditions: [
      PushCondition(
        kind: 'event_property_is',
        key: _relationTypeKey,
        value: _annotation,
      ),
    ],
  );
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
      await ensureEncryptedReactionPushRule(client);
      _done = true;
    } catch (e) {
      debugPrint('zuno/push: could not install the reaction push rule: $e');
    } finally {
      _running = false;
    }
  }
}
