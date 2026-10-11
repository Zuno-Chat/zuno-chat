import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/onboarding/onboarding_step.dart';

List<OnboardingStep> steps({
  bool justRegistered = false,
  bool notificationsAllowed = true,
  bool canAskNotifications = false,
  bool canChooseDelivery = true,
  bool needsBatteryExemption = false,
  bool needsAutostart = false,
  bool recoveryExists = true,
  bool thisDeviceHasIdentityKeys = true,
  bool hasConversations = true,
  bool recoveryPromptOnCooldown = false,
  Set<OnboardingStep> alreadyShown = const {OnboardingStep.deliveryMethod},
  bool confirmPeopleShown = true,
}) => onboardingSteps(
  justRegistered: justRegistered,
  notificationsAllowed: notificationsAllowed,
  canAskNotifications: canAskNotifications,
  canChooseDelivery: canChooseDelivery,
  needsBatteryExemption: needsBatteryExemption,
  needsAutostart: needsAutostart,
  recoveryExists: recoveryExists,
  thisDeviceHasIdentityKeys: thisDeviceHasIdentityKeys,
  hasConversations: hasConversations,
  recoveryPromptOnCooldown: recoveryPromptOnCooldown,
  alreadyShown: {
    ...alreadyShown,
    if (confirmPeopleShown) OnboardingStep.confirmPeople,
  },
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
          needsBatteryExemption: true,
          needsAutostart: true,
          thisDeviceHasIdentityKeys: false,
          alreadyShown: const {
            OnboardingStep.welcome,
            OnboardingStep.profile,
            OnboardingStep.notifications,
            OnboardingStep.deliveryMethod,
            OnboardingStep.batteryExemption,
            OnboardingStep.autostart,
            OnboardingStep.approveDevice,
          },
        ),
        isEmpty,
      );
    });
  });

  group('a brand-new account', () {
    test('is welcomed and asked for a name even when nothing else applies', () {
      expect(steps(justRegistered: true), [
        OnboardingStep.welcome,
        OnboardingStep.profile,
      ]);
    });
  });

  group('learning to confirm people', () {
    test('an account that has never seen it is shown it once', () {
      expect(steps(confirmPeopleShown: false), [OnboardingStep.confirmPeople]);
    });

    test('a new account sees it last, after the notifications', () {
      expect(
        steps(
          justRegistered: true,
          canAskNotifications: true,
          recoveryExists: false,
          hasConversations: false,
          confirmPeopleShown: false,
        ),
        [
          OnboardingStep.welcome,
          OnboardingStep.profile,
          OnboardingStep.notifications,
          OnboardingStep.confirmPeople,
        ],
      );
    });

    test('a device waiting for approval sees it after the approval', () {
      expect(
        steps(thisDeviceHasIdentityKeys: false, confirmPeopleShown: false),
        [OnboardingStep.approveDevice, OnboardingStep.confirmPeople],
      );
    });

    test('comes after every other step', () {
      expect(
        steps(
          justRegistered: true,
          canAskNotifications: true,
          needsAutostart: true,
          recoveryExists: false,
          alreadyShown: const {},
          confirmPeopleShown: false,
        ),
        [
          OnboardingStep.welcome,
          OnboardingStep.profile,
          OnboardingStep.notifications,
          OnboardingStep.deliveryMethod,
          OnboardingStep.autostart,
          OnboardingStep.setUpRecovery,
          OnboardingStep.confirmPeople,
        ],
      );
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
          thisDeviceHasIdentityKeys: false,
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

    test('is not asked where there is only one method', () {
      expect(steps(alreadyShown: const {}, canChooseDelivery: false), isEmpty);
      expect(
        steps(
          justRegistered: true,
          canAskNotifications: true,
          alreadyShown: const {},
          canChooseDelivery: false,
          thisDeviceHasIdentityKeys: false,
        ),
        [
          OnboardingStep.welcome,
          OnboardingStep.profile,
          OnboardingStep.notifications,
          OnboardingStep.approveDevice,
        ],
      );
    });

    test('with only one method, the battery step follows it straight '
        'away', () {
      expect(
        steps(
          alreadyShown: const {},
          canChooseDelivery: false,
          needsBatteryExemption: true,
        ),
        [OnboardingStep.batteryExemption],
      );
    });
  });

  group('with notifications off', () {
    test('nothing about delivery is asked once the OS will not ask again', () {
      expect(
        steps(
          notificationsAllowed: false,
          alreadyShown: const {},
          needsBatteryExemption: true,
          needsAutostart: true,
          thisDeviceHasIdentityKeys: false,
        ),
        [OnboardingStep.approveDevice],
      );
    });

    test('nothing about delivery is asked once notifications were declined '
        'here', () {
      expect(
        steps(
          notificationsAllowed: false,
          canAskNotifications: true,
          alreadyShown: const {OnboardingStep.notifications},
          needsAutostart: true,
        ),
        isEmpty,
      );
    });

    test('delivery still follows a permission this flow is about to ask '
        'for', () {
      expect(
        steps(
          notificationsAllowed: false,
          canAskNotifications: true,
          alreadyShown: const {},
          needsAutostart: true,
        ),
        [
          OnboardingStep.notifications,
          OnboardingStep.deliveryMethod,
          OnboardingStep.autostart,
        ],
      );
    });
  });

  group('after the notification permission is answered', () {
    const before = [
      OnboardingStep.notifications,
      OnboardingStep.deliveryMethod,
      OnboardingStep.batteryExemption,
      OnboardingStep.autostart,
      OnboardingStep.approveDevice,
    ];

    test('a grant keeps the delivery steps', () {
      expect(stepsAfterNotificationsAnswer(before, allowed: true), before);
    });

    test('a refusal drops every delivery step and keeps the rest', () {
      expect(stepsAfterNotificationsAnswer(before, allowed: false), [
        OnboardingStep.notifications,
        OnboardingStep.approveDevice,
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
      final once = stepsAfterDeliveryChoice(
        before,
        needsBatteryExemption: true,
      );
      expect(stepsAfterDeliveryChoice(once, needsBatteryExemption: true), once);
    });

    test('a method that does not need it drops a pending battery step', () {
      expect(
        stepsAfterDeliveryChoice(const [
          OnboardingStep.deliveryMethod,
          OnboardingStep.batteryExemption,
          OnboardingStep.approveDevice,
        ], needsBatteryExemption: false),
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
    test('offers recovery once there is history to lose', () {
      expect(steps(recoveryExists: false, hasConversations: true), [
        OnboardingStep.setUpRecovery,
      ]);
    });
  });

  group('being allowed to wake up', () {
    test('is asked for right after notifications', () {
      expect(steps(canAskNotifications: true, needsBatteryExemption: true), [
        OnboardingStep.notifications,
        OnboardingStep.batteryExemption,
      ]);
    });
  });

  group('letting Zuno start after it is closed', () {
    test('is asked on devices that block it, after the battery step and '
        'before security', () {
      expect(
        steps(
          needsBatteryExemption: true,
          needsAutostart: true,
          thisDeviceHasIdentityKeys: false,
        ),
        [
          OnboardingStep.batteryExemption,
          OnboardingStep.autostart,
          OnboardingStep.approveDevice,
        ],
      );
    });
  });

  group('what is deliberately left out', () {
    test('no recovery step while the prompt is on cooldown', () {
      expect(
        steps(recoveryExists: false, recoveryPromptOnCooldown: true),
        isEmpty,
      );
    });
  });

  group('Skip', () {
    test('is left off the steps that ask for nothing to decline', () {
      expect(offersSkip(OnboardingStep.welcome), isFalse);
      expect(offersSkip(OnboardingStep.confirmPeople), isFalse);
      expect(offersSkip(OnboardingStep.deliveryMethod), isFalse);
    });

    test('stays on every step that asks for something', () {
      for (final step in [
        OnboardingStep.profile,
        OnboardingStep.notifications,
        OnboardingStep.batteryExemption,
        OnboardingStep.autostart,
        OnboardingStep.approveDevice,
        OnboardingStep.setUpRecovery,
      ]) {
        expect(offersSkip(step), isTrue, reason: '$step');
      }
    });
  });
}
