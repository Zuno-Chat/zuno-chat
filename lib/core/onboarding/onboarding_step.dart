import '../security/account_security_status.dart';

enum OnboardingStep {
  welcome,
  profile,
  notifications,
  deliveryMethod,
  batteryExemption,
  autostart,
  approveDevice,
  setUpRecovery,
  confirmPeople,
}

const _deliverySteps = {
  OnboardingStep.deliveryMethod,
  OnboardingStep.batteryExemption,
  OnboardingStep.autostart,
};

const _nothingToDecline = {
  OnboardingStep.welcome,
  OnboardingStep.deliveryMethod,
  OnboardingStep.confirmPeople,
};

bool offersSkip(OnboardingStep step) => !_nothingToDecline.contains(step);

List<OnboardingStep> onboardingSteps({
  required bool justRegistered,
  required bool notificationsAllowed,
  required bool canAskNotifications,
  required bool canChooseDelivery,
  required bool needsBatteryExemption,
  required bool needsAutostart,
  required AccountSecurityFacts securityFacts,
  required bool hasConversations,
  required bool recoveryPromptOnCooldown,
  required Set<OnboardingStep> alreadyShown,
}) {
  final steps = <OnboardingStep>[];
  if (justRegistered) {
    steps.addAll([OnboardingStep.welcome, OnboardingStep.profile]);
  }
  final askNotifications =
      canAskNotifications &&
      !alreadyShown.contains(OnboardingStep.notifications);
  if (askNotifications) steps.add(OnboardingStep.notifications);
  if (notificationsAllowed || askNotifications) {
    final askDelivery =
        canChooseDelivery &&
        !alreadyShown.contains(OnboardingStep.deliveryMethod);
    if (askDelivery) {
      steps.add(OnboardingStep.deliveryMethod);
    } else if (needsBatteryExemption) {
      steps.add(OnboardingStep.batteryExemption);
    }
    if (needsAutostart) steps.add(OnboardingStep.autostart);
  }
  if (!securityFacts.recoveryExists) {
    if (hasConversations && !recoveryPromptOnCooldown) {
      steps.add(OnboardingStep.setUpRecovery);
    }
  } else if (!securityFacts.thisDeviceHasIdentityKeys) {
    steps.add(OnboardingStep.approveDevice);
  }
  steps.add(OnboardingStep.confirmPeople);
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

List<OnboardingStep> stepsAfterNotificationsAnswer(
  List<OnboardingStep> steps, {
  required bool allowed,
}) =>
    allowed ? steps : steps.where((s) => !_deliverySteps.contains(s)).toList();
