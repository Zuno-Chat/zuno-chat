import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/onboarding/onboarding_provider.dart';
import 'package:zuno/core/security/security_prompt_provider.dart';
import 'package:zuno/core/onboarding/onboarding_step.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/core/ui/step_hero.dart';
import 'package:zuno/core/ui/step_layout.dart';
import 'package:zuno/features/onboarding/presentation/onboarding_flow_page.dart';

import '../../../helpers/fake_matrix.dart';

const _userId = '@alex:example.org';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<OnboardingStore> pumpFlow(
    WidgetTester tester,
    List<OnboardingStep> steps, {
    http.Client? httpClient,
  }) async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        matrixClientProvider.overrideWithValue(
          buildTestClient(userId: _userId, httpClient: httpClient),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OnboardingFlowPage(steps: steps),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return container.read(onboardingStoreProvider);
  }

  testWidgets('runs the steps in order and closes after the last', (
    tester,
  ) async {
    await pumpFlow(tester, [
      OnboardingStep.profile,
      OnboardingStep.setUpRecovery,
    ]);

    expect(find.text('What should people call you?'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('What should people call you?'), findsNothing);
    expect(find.text('Set up recovery'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a skipped step is recorded, so it is not asked again', (
    tester,
  ) async {
    final store = await pumpFlow(tester, [OnboardingStep.profile]);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(store.shown(_userId), {OnboardingStep.profile});
  });

  testWidgets('a single-step flow keeps Skip but shows no progress dots', (
    tester,
  ) async {
    await pumpFlow(tester, [OnboardingStep.profile]);

    expect(find.text('Skip'), findsOneWidget);
    expect(find.byKey(onboardingDotsKey), findsNothing);
  });

  testWidgets('a multi-step flow shows where you are', (tester) async {
    await pumpFlow(tester, [
      OnboardingStep.profile,
      OnboardingStep.setUpRecovery,
    ]);

    expect(find.byKey(onboardingDotsKey), findsOneWidget);
  });

  testWidgets('swiping does nothing — only finishing or skipping moves on', (
    tester,
  ) async {
    final store = await pumpFlow(tester, [
      OnboardingStep.profile,
      OnboardingStep.setUpRecovery,
    ]);

    await tester.fling(find.byType(PageView), const Offset(-600, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('What should people call you?'), findsOneWidget);
    expect(find.text('Set up recovery'), findsNothing);
    expect(store.shown(_userId), isEmpty);
  });

  testWidgets('Skip sits at the top right, the dots at the bottom centre', (
    tester,
  ) async {
    await pumpFlow(tester, [
      OnboardingStep.profile,
      OnboardingStep.setUpRecovery,
    ]);

    final skip = tester.getCenter(find.text('Skip'));
    final dots = tester.getCenter(find.byKey(onboardingDotsKey));
    final button = tester.getRect(find.byType(FilledButton));
    final size = tester.getSize(find.byType(Scaffold).last);
    expect(skip.dx, greaterThan(size.width / 2));
    expect(skip.dy, lessThan(size.height / 4));
    expect(dots.dx, closeTo(size.width / 2, 1));
    expect(dots.dy, greaterThan(button.bottom));
    expect(tester.getTopLeft(find.byType(StepHero)).dy, greaterThan(skip.dy));
  });

  testWidgets('the main button sits at the same height on every step', (
    tester,
  ) async {
    await pumpFlow(tester, [
      OnboardingStep.welcome,
      OnboardingStep.profile,
      OnboardingStep.setUpRecovery,
    ]);

    final bottoms = <double>[];
    for (var i = 0; i < 3; i++) {
      bottoms.add(tester.getRect(find.byType(FilledButton)).bottom);
      if (i < 2) {
        await tester.tap(find.text('Skip'));
        await tester.pumpAndSettle();
      }
    }
    expect(bottoms[1], closeTo(bottoms[0], 0.5));
    expect(bottoms[2], closeTo(bottoms[0], 0.5));
  });

  testWidgets('a single step keeps its button where a longer flow has it', (
    tester,
  ) async {
    await pumpFlow(tester, [OnboardingStep.welcome, OnboardingStep.profile]);
    final withDots = tester.getRect(find.byType(FilledButton)).bottom;

    await tester.pumpWidget(const SizedBox());
    await pumpFlow(tester, [OnboardingStep.welcome]);
    expect(
      tester.getRect(find.byType(FilledButton)).bottom,
      closeTo(withDots, 0.5),
    );
  });

  testWidgets('every step centres its icon circle, title and text', (
    tester,
  ) async {
    await pumpFlow(tester, OnboardingStep.values);

    final width = tester.getSize(find.byType(Scaffold).last).width;
    for (final step in OnboardingStep.values) {
      expect(
        tester.getCenter(find.byType(StepHero)).dx,
        closeTo(width / 2, 1),
        reason: '$step',
      );
      final aligned = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(StepLayout),
              matching: find.byType(Text),
            ),
          )
          .where((text) => text.textAlign == TextAlign.center);
      expect(aligned.length, 2, reason: '$step');
      if (step != OnboardingStep.values.last) {
        await tester.tap(find.text('Skip'));
        await tester.pumpAndSettle();
      }
    }
  });

  group('the photo circle on the name step', () {
    const channel = MethodChannel('plugins.flutter.io/image_picker');
    late List<String> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return null;
          });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    testWidgets('is the picker: one circle, announced as a button', (
      tester,
    ) async {
      await pumpFlow(tester, [OnboardingStep.profile]);

      expect(find.byType(StepHero), findsOneWidget);
      expect(find.bySemanticsLabel('Add a photo'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsNothing);

      await tester.tap(find.byType(StepHero));
      await tester.pump();
      expect(calls, hasLength(1));
    });

    testWidgets('the camera badge opens the picker from any part of it', (
      tester,
    ) async {
      await pumpFlow(tester, [OnboardingStep.profile]);

      final badge = tester.getRect(find.byIcon(Icons.photo_camera_outlined));
      for (final point in [
        badge.center,
        badge.bottomRight - const Offset(1, 1),
        badge.centerRight - const Offset(1, 0),
      ]) {
        await tester.tapAt(point);
        await tester.pump();
      }
      expect(calls, hasLength(3));
    });
  });

  testWidgets('with the keyboard open the name step does not overflow and '
      'Save stays above the keyboard', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await pumpFlow(tester, [
      OnboardingStep.profile,
      OnboardingStep.setUpRecovery,
    ]);

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byType(FilledButton)).bottom,
      lessThanOrEqualTo(640 - 300),
    );
  });

  group('the keyboard on the name step', () {
    final nameField = find.widgetWithText(TextField, 'Name');
    final nameStep = find.text('What should people call you?');

    testWidgets('stays closed until the field is tapped', (tester) async {
      await pumpFlow(tester, [OnboardingStep.profile]);

      final editable = tester.widget<EditableText>(
        find.descendant(of: nameField, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('closes as soon as Save is tapped', (tester) async {
      await pumpFlow(tester, [
        OnboardingStep.profile,
        OnboardingStep.setUpRecovery,
      ], httpClient: MockClient((_) async => http.Response('{}', 200)));
      await tester.showKeyboard(nameField);
      await tester.enterText(nameField, 'Alex');
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(tester.testTextInput.isVisible, isFalse);
      expect(nameStep, findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('closes when the step is skipped', (tester) async {
      await pumpFlow(tester, [
        OnboardingStep.profile,
        OnboardingStep.setUpRecovery,
      ]);
      await tester.showKeyboard(nameField);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.tap(find.text('Skip'));
      await tester.pump();

      expect(tester.testTextInput.isVisible, isFalse);
      await tester.pumpAndSettle();
    });

    testWidgets('Done on an empty name closes it without moving on', (
      tester,
    ) async {
      await pumpFlow(tester, [
        OnboardingStep.profile,
        OnboardingStep.setUpRecovery,
      ]);
      await tester.showKeyboard(nameField);
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(tester.testTextInput.isVisible, isFalse);
      expect(nameStep, findsOneWidget);
    });
  });

  testWidgets('the welcome page says why, and its button gets started', (
    tester,
  ) async {
    final store = await pumpFlow(tester, [OnboardingStep.welcome]);

    expect(find.text('Welcome to Zuno'), findsOneWidget);
    expect(find.textContaining('advertisers'), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget);
    expect(store.shown(_userId), {OnboardingStep.welcome});
  });

  group('choosing how messages arrive', () {
    void stubBatteryExemption({required bool granted}) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('zuno/background_sync'),
            (call) async => switch (call.method) {
              'isIgnoringBatteryOptimizations' ||
              'isPackageIgnoringBatteryOptimizations' => granted,
              _ => null,
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('zuno/background_sync'),
              null,
            ),
      );
    }

    testWidgets('lists every method with the current one preselected', (
      tester,
    ) async {
      await pumpFlow(tester, [OnboardingStep.deliveryMethod]);

      expect(find.text('Google services'), findsOneWidget);
      expect(find.text('UnifiedPush'), findsOneWidget);
      expect(find.text('Background sync'), findsOneWidget);
      expect(
        tester
            .widget<RadioGroup<NotificationDeliveryMode>>(
              find.byType(RadioGroup<NotificationDeliveryMode>),
            )
            .groupValue,
        NotificationDeliveryMode.fcm,
      );
    });

    testWidgets('a method that needs the battery exemption adds that step '
        'next, and the choice is saved', (tester) async {
      stubBatteryExemption(granted: false);
      final store = await pumpFlow(tester, [
        OnboardingStep.deliveryMethod,
        OnboardingStep.setUpRecovery,
      ]);

      await tester.tap(find.text('UnifiedPush'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Let Zuno wake up'), findsOneWidget);
      expect(store.shown(_userId), {OnboardingStep.deliveryMethod});
      expect(
        prefs.getString('settings.notification_delivery_mode'),
        'unifiedPush',
      );
    });

    testWidgets('a method that needs it skips the battery step when Android '
        'already exempts the app', (tester) async {
      stubBatteryExemption(granted: true);
      await pumpFlow(tester, [
        OnboardingStep.deliveryMethod,
        OnboardingStep.setUpRecovery,
      ]);

      await tester.tap(find.text('Background sync'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Set up recovery'), findsOneWidget);
    });

    testWidgets('Google services drops a battery step that was pending', (
      tester,
    ) async {
      stubBatteryExemption(granted: false);
      await pumpFlow(tester, [
        OnboardingStep.deliveryMethod,
        OnboardingStep.batteryExemption,
        OnboardingStep.setUpRecovery,
      ]);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Set up recovery'), findsOneWidget);
      expect(find.text('Let Zuno wake up'), findsNothing);
    });
  });

  testWidgets('every step is one page with one primary button', (tester) async {
    for (final step in OnboardingStep.values) {
      await pumpFlow(tester, [step]);

      expect(find.byType(FilledButton), findsOneWidget, reason: '$step');
      expect(find.text('Skip'), findsOneWidget, reason: '$step');

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('the notifications step asks one question only', (tester) async {
    await pumpFlow(tester, [OnboardingStep.notifications]);

    expect(find.text('All messages'), findsNothing);
    expect(find.text('Only when someone mentions you'), findsNothing);
  });

  testWidgets('skipping the recovery step still starts its cooldown', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        matrixClientProvider.overrideWithValue(
          buildTestClient(userId: _userId),
        ),
      ],
    );
    addTearDown(container.dispose);
    final promptStore = container.read(securityPromptStoreProvider);
    expect(promptStore.lastPrompted(), isNull);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: OnboardingFlowPage(steps: [OnboardingStep.setUpRecovery]),
        ),
      ),
    );
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(promptStore.lastPrompted(), isNotNull);
  });
}
