import '../security/account_security_status.dart';

enum OnboardingStep {
  welcome,
  profile,
  notifications,
  deliveryMethod,
  batteryExemption,
  approveDevice,
  setUpRecovery,
}

List<OnboardingStep> onboardingSteps({
  required bool justRegistered,
  required bool canAskNotifications,
  required bool needsBatteryExemption,
  required AccountSecurityFacts securityFacts,
  required bool hasConversations,
  required bool recoveryPromptOnCooldown,
  required Set<OnboardingStep> alreadyShown,
}) {
  final steps = <OnboardingStep>[];
  if (justRegistered) {
    steps.addAll([OnboardingStep.welcome, OnboardingStep.profile]);
  }
  if (canAskNotifications) steps.add(OnboardingStep.notifications);
  final askDelivery = !alreadyShown.contains(OnboardingStep.deliveryMethod);
  if (askDelivery) {
    steps.add(OnboardingStep.deliveryMethod);
  } else if (needsBatteryExemption) {
    steps.add(OnboardingStep.batteryExemption);
  }
  if (!securityFacts.recoveryExists) {
    if (hasConversations && !recoveryPromptOnCooldown) {
      steps.add(OnboardingStep.setUpRecovery);
    }
  } else if (!securityFacts.thisDeviceHasIdentityKeys) {
    steps.add(OnboardingStep.approveDevice);
  }
  return steps.where((step) => !alreadyShown.contains(step)).toList();
}

List<OnboardingStep> stepsAfterDeliveryChoice(
  List<OnboardingStep> steps, {
  required bool needsBatteryExemption,
}) {
  final result = steps
      .where((s) => s != OnboardingStep.batteryExemption)
      .toList();
  if (!needsBatteryExemption) return result;
  final after = result.indexOf(OnboardingStep.deliveryMethod);
  result.insert(after + 1, OnboardingStep.batteryExemption);
  return result;
}
