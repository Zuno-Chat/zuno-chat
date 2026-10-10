import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/server_push_rules.dart';

import '../../helpers/fake_matrix.dart';

Map<String, Object?> _ruleJson(
  SilentRelationRule rule, {
  List<Object?> actions = const [],
  String? value,
}) => {
  'rule_id': rule.ruleId,
  'default': false,
  'enabled': true,
  'actions': actions,
  'conditions': [
    {
      'kind': 'event_property_is',
      'key': r'content.m\.relates_to.rel_type',
      'value': value ?? rule.relType,
    },
  ],
};

Map<String, Object?> _messageRuleJson({
  List<Object?> actions = const [
    'notify',
    {'set_tweak': 'highlight', 'value': false},
  ],
  bool enabled = true,
}) => {
  'rule_id': '.m.rule.message',
  'default': true,
  'enabled': enabled,
  'actions': actions,
  'conditions': [
    {'kind': 'event_match', 'key': 'type', 'pattern': 'm.room.message'},
  ],
};

PushRuleSet _rules({
  List<Map<String, Object?>> override = const [],
  List<Map<String, Object?>> underride = const [],
}) => PushRuleSet.fromJson({'override': override, 'underride': underride});

({Client client, List<http.Request> puts}) _clientWithServer({
  Map<String, Object?>? pushRules,
}) {
  final puts = <http.Request>[];
  final client = buildTestClient(
    userId: '@me:example.org',
    deviceId: 'DEV',
    httpClient: MockClient((request) async {
      if (request.method == 'PUT' && request.url.path.contains('/pushrules/')) {
        puts.add(request);
      }
      return http.Response('{}', 200);
    }),
  );
  client.baseUri = Uri.parse('https://example.org');
  client.bearerToken = 'test-token';
  if (pushRules != null) {
    client.accountData['m.push_rules'] = BasicEvent(
      type: 'm.push_rules',
      content: {'global': pushRules},
    );
  }
  return (client: client, puts: puts);
}

void main() {
  group('silentRelationRuleIsCurrent', () {
    for (final rule in silentRelationRules) {
      group(rule.ruleId, () {
        test('is false without any rules, so nothing is decided blind', () {
          expect(silentRelationRuleIsCurrent(null, rule), isFalse);
        });

        test('is false when the rule is missing', () {
          expect(silentRelationRuleIsCurrent(_rules(), rule), isFalse);
        });

        test('is true when the rule is present and silent', () {
          expect(
            silentRelationRuleIsCurrent(
              _rules(override: [_ruleJson(rule)]),
              rule,
            ),
            isTrue,
          );
        });

        test('is false when the rule exists but would notify', () {
          expect(
            silentRelationRuleIsCurrent(
              _rules(
                override: [
                  _ruleJson(rule, actions: ['notify']),
                ],
              ),
              rule,
            ),
            isFalse,
          );
        });

        test('is false when the rule matches another relation', () {
          expect(
            silentRelationRuleIsCurrent(
              _rules(override: [_ruleJson(rule, value: 'm.replace')]),
              rule,
            ),
            isFalse,
          );
        });
      });
    }
  });

  group('ensureSilentRelationRule', () {
    test(
      'installs a silent override on the relation type when missing',
      () async {
        final env = _clientWithServer(pushRules: {'override': []});

        await ensureSilentRelationRule(env.client, referenceRule);

        expect(
          env.puts.single.url.path,
          endsWith('/pushrules/global/override/${referenceRule.ruleId}'),
        );
        final body = jsonDecode(env.puts.single.body) as Map;
        expect(body['actions'], isEmpty);
        final condition = (body['conditions'] as List).single as Map;
        expect(condition['kind'], 'event_property_is');
        expect(condition['key'], r'content.m\.relates_to.rel_type');
        expect(condition['value'], 'm.reference');
      },
    );

    test('leaves the server alone when the rule is already there', () async {
      final env = _clientWithServer(
        pushRules: {
          'override': [_ruleJson(referenceRule)],
        },
      );

      await ensureSilentRelationRule(env.client, referenceRule);

      expect(env.puts, isEmpty);
    });

    test('does nothing before the push rules have been synced', () async {
      final env = _clientWithServer();

      await ensureSilentRelationRule(env.client, encryptedReactionRule);

      expect(env.puts, isEmpty);
    });
  });

  group('messageRuleNeedsSound', () {
    test('is true for the default rule, which notifies without a sound', () {
      expect(
        messageRuleNeedsSound(_rules(underride: [_messageRuleJson()])),
        isTrue,
      );
    });

    test('is false once the rule carries a sound', () {
      expect(
        messageRuleNeedsSound(
          _rules(
            underride: [
              _messageRuleJson(
                actions: [
                  'notify',
                  {'set_tweak': 'sound', 'value': 'default'},
                ],
              ),
            ],
          ),
        ),
        isFalse,
      );
    });

    test('leaves a rule the user turned off or silenced alone', () {
      expect(
        messageRuleNeedsSound(
          _rules(underride: [_messageRuleJson(enabled: false)]),
        ),
        isFalse,
      );
      expect(
        messageRuleNeedsSound(
          _rules(underride: [_messageRuleJson(actions: const [])]),
        ),
        isFalse,
      );
    });

    test('is false with no rules or no message rule', () {
      expect(messageRuleNeedsSound(null), isFalse);
      expect(messageRuleNeedsSound(_rules()), isFalse);
    });
  });

  test('ensureMessageRuleSound keeps the actions and adds the sound', () async {
    final env = _clientWithServer(
      pushRules: {
        'underride': [_messageRuleJson()],
      },
    );

    await ensureMessageRuleSound(env.client);

    expect(
      env.puts.single.url.path,
      endsWith('/pushrules/global/underride/.m.rule.message/actions'),
    );
    final body = jsonDecode(env.puts.single.body) as Map;
    expect(body['actions'], [
      'notify',
      {'set_tweak': 'highlight', 'value': false},
      {'set_tweak': 'sound', 'value': 'default'},
    ]);
  });

  group('pushRuleMaintenanceProvider', () {
    test('installs every rule once the first sync brings the rules, and only '
        'once', () async {
      final env = _clientWithServer();
      final container = ProviderContainer(
        overrides: [matrixClientProvider.overrideWithValue(env.client)],
      );
      addTearDown(container.dispose);
      container.read(pushRuleMaintenanceProvider);

      env.client.onSync.add(SyncUpdate(nextBatch: '1'));
      await pumpEventQueue();
      expect(env.puts, isEmpty, reason: 'rules not synced yet');

      env.client.accountData['m.push_rules'] = BasicEvent(
        type: 'm.push_rules',
        content: {
          'global': {
            'override': <Object?>[],
            'underride': [_messageRuleJson()],
          },
        },
      );
      env.client.onSync.add(SyncUpdate(nextBatch: '2'));
      await pumpEventQueue();
      env.client.onSync.add(SyncUpdate(nextBatch: '3'));
      await pumpEventQueue();

      expect(env.puts.map((r) => r.url.path.split('/pushrules/global/').last), [
        'override/${encryptedReactionRule.ruleId}',
        'override/${referenceRule.ruleId}',
        'underride/.m.rule.message/actions',
      ]);
    });
  });
}
