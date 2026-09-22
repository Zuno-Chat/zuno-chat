import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/encrypted_reaction_push_rule.dart';

import '../../helpers/fake_matrix.dart';

Map<String, Object?> _ruleJson({
  List<Object?> actions = const [],
  String value = 'm.annotation',
}) => {
  'rule_id': encryptedReactionRuleId,
  'default': false,
  'enabled': true,
  'actions': actions,
  'conditions': [
    {
      'kind': 'event_property_is',
      'key': r'content.m\.relates_to.rel_type',
      'value': value,
    },
  ],
};

PushRuleSet _rules({List<Map<String, Object?>> override = const []}) =>
    PushRuleSet.fromJson({'override': override});

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
  group('encryptedReactionRuleIsCurrent', () {
    test('is false without any rules, so nothing is decided blind', () {
      expect(encryptedReactionRuleIsCurrent(null), isFalse);
    });

    test('is false when the rule is missing', () {
      expect(encryptedReactionRuleIsCurrent(_rules()), isFalse);
    });

    test('is true when the rule is present and silent', () {
      expect(
        encryptedReactionRuleIsCurrent(_rules(override: [_ruleJson()])),
        isTrue,
      );
    });

    test('is false when the rule exists but would notify', () {
      expect(
        encryptedReactionRuleIsCurrent(
          _rules(
            override: [
              _ruleJson(actions: ['notify']),
            ],
          ),
        ),
        isFalse,
      );
    });

    test('is false when the rule matches something else', () {
      expect(
        encryptedReactionRuleIsCurrent(
          _rules(override: [_ruleJson(value: 'm.replace')]),
        ),
        isFalse,
      );
    });
  });

  group('ensureEncryptedReactionPushRule', () {
    test(
      'installs a silent override on the relation type when missing',
      () async {
        final env = _clientWithServer(pushRules: {'override': []});

        await ensureEncryptedReactionPushRule(env.client);

        expect(env.puts, hasLength(1));
        expect(
          env.puts.single.url.path,
          endsWith('/pushrules/global/override/$encryptedReactionRuleId'),
        );
        final body = jsonDecode(env.puts.single.body) as Map;
        expect(body['actions'], isEmpty);
        final condition = (body['conditions'] as List).single as Map;
        expect(condition['kind'], 'event_property_is');
        expect(condition['key'], r'content.m\.relates_to.rel_type');
        expect(condition['value'], 'm.annotation');
      },
    );

    test('leaves the server alone when the rule is already there', () async {
      final env = _clientWithServer(
        pushRules: {
          'override': [_ruleJson()],
        },
      );

      await ensureEncryptedReactionPushRule(env.client);

      expect(env.puts, isEmpty);
    });

    test('does nothing before the push rules have been synced', () async {
      final env = _clientWithServer();

      await ensureEncryptedReactionPushRule(env.client);

      expect(env.puts, isEmpty);
    });
  });

  group('pushRuleMaintenanceProvider', () {
    test('installs the rule once the first sync brings the rules, and only '
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
          'global': {'override': []},
        },
      );
      env.client.onSync.add(SyncUpdate(nextBatch: '2'));
      await pumpEventQueue();
      env.client.onSync.add(SyncUpdate(nextBatch: '3'));
      await pumpEventQueue();

      expect(env.puts, hasLength(1));
    });
  });
}
