import '../onboarding/onboarding_step.dart';
import 'account_security_status.dart';

enum SecurityPromptDecision {
  none,
  setUpRecovery,
}

const securityPromptFirstUseDelay = Duration(days: 3);

const securityPromptCooldown = Duration(days: 7);

SecurityPromptDecision securityPromptDecision({
  required AccountSecurityStatus status,
  required DateTime firstUse,
  required DateTime? lastPrompted,
  required DateTime now,
  required int deviceCount,
  required bool hasConversations,
}) {
  if (status != AccountSecurityStatus.noRecovery) {
    return SecurityPromptDecision.none;
  }
  if (!hasConversations) return SecurityPromptDecision.none;
  if (lastPrompted != null &&
      now.difference(lastPrompted) < securityPromptCooldown) {
    return SecurityPromptDecision.none;
  }
  final secondDeviceAppeared = deviceCount > 1;
  final usedLongEnough =
      now.difference(firstUse) >= securityPromptFirstUseDelay;
  return secondDeviceAppeared || usedLongEnough
      ? SecurityPromptDecision.setUpRecovery
      : SecurityPromptDecision.none;
}

bool recoveryPromptDefersToOnboarding({
  required bool flowInProgress,
  required List<OnboardingStep> pendingSteps,
}) => flowInProgress || pendingSteps.isNotEmpty;
