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
  bool notificationsAllowed = true,
  bool canAskNotifications = false,
  bool canChooseDelivery = true,
  bool needsBatteryExemption = false,
  bool needsAutostart = false,
  AccountSecurityFacts? securityFacts,
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
  securityFacts: securityFacts ?? facts(),
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

    test('is welcomed and asked for a name even when nothing else applies', () {
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

  group('learning to confirm people', () {
    test('an account that has never seen it is shown it once', () {
      expect(steps(confirmPeopleShown: false), [OnboardingStep.confirmPeople]);
    });

    test('a new account sees it last, after the notifications', () {
      expect(
        steps(
          justRegistered: true,
          canAskNotifications: true,
          securityFacts: noRecovery,
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
      expect(steps(securityFacts: lockedDevice, confirmPeopleShown: false), [
        OnboardingStep.approveDevice,
        OnboardingStep.confirmPeople,
      ]);
    });

    test('comes after every other step', () {
      expect(
        steps(
          justRegistered: true,
          canAskNotifications: true,
          needsAutostart: true,
          securityFacts: noRecovery,
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

    test(
      'stays last once the battery step joins after the delivery choice',
      () {
        expect(
          stepsAfterDeliveryChoice(const [
            OnboardingStep.deliveryMethod,
            OnboardingStep.approveDevice,
            OnboardingStep.confirmPeople,
          ], needsBatteryExemption: true),
          [
            OnboardingStep.deliveryMethod,
            OnboardingStep.batteryExemption,
            OnboardingStep.approveDevice,
            OnboardingStep.confirmPeople,
          ],
        );
      },
    );

    test('once shown it is never shown again', () {
      expect(steps(), isEmpty);
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

    test('is not asked where there is only one method', () {
      expect(steps(alreadyShown: const {}, canChooseDelivery: false), isEmpty);
      expect(
        steps(
          justRegistered: true,
          canAskNotifications: true,
          alreadyShown: const {},
          canChooseDelivery: false,
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
          securityFacts: lockedDevice,
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
      expect(steps(canAskNotifications: true, needsBatteryExemption: true), [
        OnboardingStep.notifications,
        OnboardingStep.batteryExemption,
      ]);
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
      expect(steps(needsBatteryExemption: true, securityFacts: lockedDevice), [
        OnboardingStep.batteryExemption,
        OnboardingStep.approveDevice,
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
          securityFacts: lockedDevice,
        ),
        [
          OnboardingStep.batteryExemption,
          OnboardingStep.autostart,
          OnboardingStep.approveDevice,
        ],
      );
    });

    test('is not asked twice', () {
      expect(
        steps(
          needsAutostart: true,
          alreadyShown: const {
            OnboardingStep.deliveryMethod,
            OnboardingStep.autostart,
          },
        ),
        isEmpty,
      );
    });

    test('is not asked on devices that do not block it', () {
      expect(steps(needsAutostart: false), isEmpty);
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
