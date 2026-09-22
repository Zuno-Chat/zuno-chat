import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/onboarding/onboarding_step.dart';
import 'package:zuno/core/security/security_prompt.dart';

void main() {
  test('the dialog steps aside while onboarding still has steps to ask', () {
    expect(
      recoveryPromptDefersToOnboarding(
        flowInProgress: false,
        pendingSteps: const [OnboardingStep.setUpRecovery],
      ),
      isTrue,
    );
    expect(
      recoveryPromptDefersToOnboarding(
        flowInProgress: false,
        pendingSteps: const [OnboardingStep.notifications],
      ),
      isTrue,
    );
  });

  test('the dialog steps aside while the flow is open', () {
    expect(
      recoveryPromptDefersToOnboarding(
        flowInProgress: true,
        pendingSteps: const [],
      ),
      isTrue,
    );
  });

  test('the dialog goes ahead once onboarding has nothing left', () {
    expect(
      recoveryPromptDefersToOnboarding(
        flowInProgress: false,
        pendingSteps: const [],
      ),
      isFalse,
    );
  });
}
