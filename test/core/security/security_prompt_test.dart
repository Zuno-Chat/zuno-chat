import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/security/account_security_status.dart';
import 'package:zuno/core/security/security_prompt.dart';

final _now = DateTime(2026, 9, 4, 12);

SecurityPromptDecision _decide({
  AccountSecurityStatus status = AccountSecurityStatus.noRecovery,
  Duration usedFor = const Duration(days: 1),
  Duration? promptedAgo,
  int deviceCount = 1,
  bool hasConversations = true,
}) => securityPromptDecision(
  status: status,
  firstUse: _now.subtract(usedFor),
  lastPrompted: promptedAgo == null ? null : _now.subtract(promptedAgo),
  now: _now,
  deviceCount: deviceCount,
  hasConversations: hasConversations,
);

void main() {
  group('securityPromptDecision', () {
    test('a second device appearing prompts immediately', () {
      expect(_decide(deviceCount: 2), SecurityPromptDecision.setUpRecovery);
    });

    test('a few days of use prompts on its own', () {
      expect(
        _decide(usedFor: securityPromptFirstUseDelay),
        SecurityPromptDecision.setUpRecovery,
      );
    });

    test('an empty account is never prompted, whatever the trigger', () {
      expect(
        _decide(deviceCount: 2, hasConversations: false),
        SecurityPromptDecision.none,
      );
      expect(
        _decide(usedFor: securityPromptFirstUseDelay, hasConversations: false),
        SecurityPromptDecision.none,
      );
    });

    test("an empty account doesn't burn its cooldown either", () {
      expect(
        _decide(deviceCount: 2, hasConversations: false),
        SecurityPromptDecision.none,
      );
      expect(_decide(deviceCount: 2), SecurityPromptDecision.setUpRecovery);
    });

    test('a brand new single-device account is left alone', () {
      expect(_decide(), SecurityPromptDecision.none);
    });

    test('an account that already has recovery is never prompted', () {
      for (final status in AccountSecurityStatus.values) {
        if (status == AccountSecurityStatus.noRecovery) continue;
        expect(
          _decide(
            status: status,
            deviceCount: 4,
            usedFor: const Duration(days: 90),
          ),
          SecurityPromptDecision.none,
          reason: status.name,
        );
      }
    });

    test('"not now" is respected for the whole cooldown', () {
      expect(
        _decide(deviceCount: 2, promptedAgo: const Duration(days: 1)),
        SecurityPromptDecision.none,
      );
    });

    test('asks again once the cooldown has passed', () {
      expect(
        _decide(deviceCount: 2, promptedAgo: securityPromptCooldown),
        SecurityPromptDecision.setUpRecovery,
      );
    });
  });
}
