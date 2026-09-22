import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/onboarding/onboarding_step.dart';
import 'package:zuno/core/security/account_security_status.dart';

AccountSecurityFacts facts({
  bool recoveryExists = true,
  bool thisDeviceHasIdentityKeys = true,
  int unapprovedOtherDevices = 0,
}) => AccountSecurityFacts(
  recoveryExists: recoveryExists,
  thisDeviceHasIdentityKeys: thisDeviceHasIdentityKeys,
  keyBackupExists: recoveryExists,
  keyBackupUsableHere: thisDeviceHasIdentityKeys,
  unapprovedOtherDevices: unapprovedOtherDevices,
);

final lockedDevice = facts(thisDeviceHasIdentityKeys: false);

final noRecovery = facts(recoveryExists: false);

List<OnboardingStep> steps({
  bool justRegistered = false,
  bool canAskNotifications = false,
  bool needsBatteryExemption = false,
  AccountSecurityFacts? securityFacts,
  bool hasConversations = true,
  bool recoveryPromptOnCooldown = false,
  Set<OnboardingStep> alreadyShown = const {OnboardingStep.deliveryMethod},
}) => onboardingSteps(
  justRegistered: justRegistered,
  canAskNotifications: canAskNotifications,
  needsBatteryExemption: needsBatteryExemption,
  securityFacts: securityFacts ?? facts(),
  hasConversations: hasConversations,
  recoveryPromptOnCooldown: recoveryPromptOnCooldown,
  alreadyShown: alreadyShown,
);

void main() {
  group('the common case', () {
    test('a settled account is asked nothing at all', () {
      expect(steps(), isEmpty);
    });

    test('every step already shown once is never asked again', () {
      expect(
        steps(
          justRegistered: true,
          canAskNotifications: true,
          securityFacts: lockedDevice,
          alreadyShown: const {
            OnboardingStep.welcome,
            OnboardingStep.profile,
            OnboardingStep.notifications,
            OnboardingStep.deliveryMethod,
            OnboardingStep.approveDevice,
          },
        ),
        isEmpty,
      );
    });
  });

  group('a brand-new account', () {
    test('is welcomed and asked for a name, and nothing else', () {
      expect(
        steps(
          justRegistered: true,
          canAskNotifications: true,
          securityFacts: noRecovery,
          hasConversations: false,
        ),
        [
          OnboardingStep.welcome,
          OnboardingStep.profile,
          OnboardingStep.notifications,
        ],
      );
    });

    test('is welcomed and asked for a name even when nothing else applies',
        () {
      expect(steps(justRegistered: true), [
        OnboardingStep.welcome,
        OnboardingStep.profile,
      ]);
    });

    test('is not welcomed or asked for a name a second time', () {
      expect(
        steps(
          justRegistered: true,
          alreadyShown: {
            OnboardingStep.welcome,
            OnboardingStep.profile,
            OnboardingStep.deliveryMethod,
          },
        ),
        isEmpty,
      );
    });
  });

  group('signing in', () {
    test('never welcomes or asks for a name — those are registration\'s '
        'steps', () {
      expect(steps(justRegistered: false), isEmpty);
    });
  });

  group('choosing how messages arrive', () {
    test('is asked once per device, on login as well as registration', () {
      expect(steps(alreadyShown: const {}), [OnboardingStep.deliveryMethod]);
      expect(steps(justRegistered: true, alreadyShown: const {}), [
        OnboardingStep.welcome,
        OnboardingStep.profile,
        OnboardingStep.deliveryMethod,
      ]);
    });

    test('comes after the notification permission and before security', () {
      expect(
        steps(
          alreadyShown: const {},
          canAskNotifications: true,
          securityFacts: lockedDevice,
        ),
        [
          OnboardingStep.notifications,
          OnboardingStep.deliveryMethod,
          OnboardingStep.approveDevice,
        ],
      );
    });

    test('holds the battery step back until the method is chosen', () {
      expect(steps(alreadyShown: const {}, needsBatteryExemption: true), [
        OnboardingStep.deliveryMethod,
      ]);
    });

    test('once answered, the battery step follows the stored method', () {
      expect(steps(needsBatteryExemption: true), [
        OnboardingStep.batteryExemption,
      ]);
    });
  });

  group('after a delivery method is chosen', () {
    const before = [
      OnboardingStep.notifications,
      OnboardingStep.deliveryMethod,
      OnboardingStep.approveDevice,
    ];

    test('a method that needs the battery exemption adds that step right '
        'after', () {
      expect(stepsAfterDeliveryChoice(before, needsBatteryExemption: true), [
        OnboardingStep.notifications,
        OnboardingStep.deliveryMethod,
        OnboardingStep.batteryExemption,
        OnboardingStep.approveDevice,
      ]);
    });

    test('never adds it twice', () {
      final once = stepsAfterDeliveryChoice(before, needsBatteryExemption: true);
      expect(stepsAfterDeliveryChoice(once, needsBatteryExemption: true), once);
    });

    test('a method that does not need it drops a pending battery step', () {
      expect(
        stepsAfterDeliveryChoice(
          const [
            OnboardingStep.deliveryMethod,
            OnboardingStep.batteryExemption,
            OnboardingStep.approveDevice,
          ],
          needsBatteryExemption: false,
        ),
        [OnboardingStep.deliveryMethod, OnboardingStep.approveDevice],
      );
    });

    test('leaves the list alone when nothing changes', () {
      expect(
        stepsAfterDeliveryChoice(before, needsBatteryExemption: false),
        before,
      );
    });
  });

  group('signing in to an established account', () {
    test('leads with unlocking the history', () {
      expect(steps(securityFacts: lockedDevice), [
        OnboardingStep.approveDevice,
      ]);
    });

    test('offers recovery once there is history to lose', () {
      expect(steps(securityFacts: noRecovery, hasConversations: true), [
        OnboardingStep.setUpRecovery,
      ]);
    });

    test('runs the steps welcome-first, security-last', () {
      expect(
        steps(
          justRegistered: true,
          canAskNotifications: true,
          securityFacts: lockedDevice,
        ),
        [
          OnboardingStep.welcome,
          OnboardingStep.profile,
          OnboardingStep.notifications,
          OnboardingStep.approveDevice,
        ],
      );
    });
  });

  group('being allowed to wake up', () {
    test('is asked for right after notifications', () {
      expect(
        steps(canAskNotifications: true, needsBatteryExemption: true),
        [OnboardingStep.notifications, OnboardingStep.batteryExemption],
      );
    });

    test('is not asked when Android already exempts the app', () {
      expect(steps(needsBatteryExemption: false), isEmpty);
    });

    test('is not asked twice', () {
      expect(
        steps(
          needsBatteryExemption: true,
          alreadyShown: const {
            OnboardingStep.deliveryMethod,
            OnboardingStep.batteryExemption,
          },
        ),
        isEmpty,
      );
    });

    test('comes before the security steps, not after them', () {
      expect(
        steps(needsBatteryExemption: true, securityFacts: lockedDevice),
        [OnboardingStep.batteryExemption, OnboardingStep.approveDevice],
      );
    });
  });

  group('what is deliberately left out', () {
    test('no notification step once the OS will not ask again', () {
      expect(steps(canAskNotifications: false), isEmpty);
    });

    test('no recovery step while the prompt is on cooldown', () {
      expect(
        steps(securityFacts: noRecovery, recoveryPromptOnCooldown: true),
        isEmpty,
      );
    });

    test('nothing for the states that belong to the Security screen', () {
      expect(steps(securityFacts: facts(unapprovedOtherDevices: 2)), isEmpty);
      expect(
        steps(
          securityFacts: const AccountSecurityFacts(
            recoveryExists: true,
            thisDeviceHasIdentityKeys: true,
            keyBackupExists: true,
            keyBackupUsableHere: false,
            unapprovedOtherDevices: 0,
          ),
        ),
        isEmpty,
      );
    });

    test('an unapproved *other* device does not mask this one being '
        'locked', () {
      expect(
        steps(
          securityFacts: facts(
            thisDeviceHasIdentityKeys: false,
            unapprovedOtherDevices: 3,
          ),
        ),
        [OnboardingStep.approveDevice],
      );
    });

    test('never asks about recovery twice in one run', () {
      final result = steps(securityFacts: lockedDevice, hasConversations: true);
      expect(result, isNot(contains(OnboardingStep.setUpRecovery)));
    });
  });
}
