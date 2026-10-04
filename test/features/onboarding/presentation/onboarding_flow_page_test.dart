import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/fcm_availability_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/notifications/notification_delivery_provider.dart';
import 'package:zuno/core/onboarding/onboarding_provider.dart';
import 'package:zuno/core/onboarding/onboarding_step.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/fcm_bridge.dart';
import 'package:zuno/core/security/security_prompt_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/core/ui/step_hero.dart';
import 'package:zuno/core/ui/step_layout.dart';
import 'package:zuno/core/ui/zuno_motion.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/onboarding/presentation/onboarding_flow_page.dart';
import 'package:zuno/features/settings/presentation/secure_backup_page.dart';
import 'package:zuno/features/verification/presentation/approve_this_device_page.dart';

import '../../../helpers/fake_encryption.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_unified_push.dart';
import '../../../helpers/platform_capabilities.dart';

const _userId = '@alex:example.org';

class _FakeImagePicker extends ImagePickerPlatform {
  XFile? answer;
  Object? error;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    final error = this.error;
    if (error != null) throw error;
    return answer;
  }
}

class _UploadingDatabaseApi extends FakeDatabaseApi {
  @override
  int get maxFileSize => 0;

  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
  getCustomCacheObject(String cacheKey) async =>
      (content: const <String, Object?>{}, savedAt: DateTime.now());
}

void main() {
  late SharedPreferences prefs;
  late List<String> channelCalls;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    channelCalls = [];
  });

  void stubNotificationPermission({required bool granted}) {
    const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final status = granted ? 1 : 0;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => switch (call.method) {
        'checkPermissionStatus' => status,
        'requestPermissions' => {17: status},
        _ => null,
      },
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  Future<OnboardingStore> pumpFlow(
    WidgetTester tester,
    List<OnboardingStep> steps, {
    http.Client? httpClient,
    PlatformCapabilities? capabilities,
    Client? client,
    AsyncValue<FcmAvailability> fcm = const AsyncData(
      FcmAvailability.available,
    ),
    bool forwardExit = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        matrixClientProvider.overrideWithValue(
          client ?? buildTestClient(userId: _userId, httpClient: httpClient),
        ),
        fcmAvailabilityProvider.overrideWithValue(fcm),
        if (capabilities != null)
          platformCapabilitiesProvider.overrideWithValue(capabilities),
      ],
    );
    addTearDown(container.dispose);
    Widget flow(BuildContext _) => OnboardingFlowPage(steps: steps);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: forwardExit ? zunoLightTheme : null,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                forwardExit
                    ? ForwardExitPageRoute(builder: flow)
                    : MaterialPageRoute(builder: flow),
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

  Finder skip() => find.text('Skip').hitTestable();

  Future<void> moveOn(WidgetTester tester) async {
    final offered = skip().evaluate().isNotEmpty;
    await tester.tap(offered ? skip() : find.byType(FilledButton));
    await tester.pumpAndSettle();
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

  testWidgets('the confirm-people card explains it and moves on', (
    tester,
  ) async {
    final store = await pumpFlow(tester, [
      OnboardingStep.confirmPeople,
      OnboardingStep.setUpRecovery,
    ]);

    expect(find.text('Make sure it is really them'), findsOneWidget);
    expect(find.textContaining('compare pictures on a call'), findsOneWidget);
    expect(find.byIcon(Icons.how_to_reg_outlined), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Set up recovery'), findsOneWidget);
    expect(store.shown(_userId), {OnboardingStep.confirmPeople});
  });

  testWidgets('a skipped step is recorded, so it is not asked again', (
    tester,
  ) async {
    final store = await pumpFlow(tester, [OnboardingStep.profile]);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(store.shown(_userId), {OnboardingStep.profile});
  });

  testWidgets('a step with nothing to decline shows no Skip; its own button '
      'moves on', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpFlow(tester, [
      OnboardingStep.welcome,
      OnboardingStep.confirmPeople,
    ]);

    expect(skip(), findsNothing);
    expect(find.bySemanticsLabel('Skip'), findsNothing);
    semantics.dispose();

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text('Make sure it is really them'), findsOneWidget);
    expect(skip(), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('Skip fades in with the slide instead of popping in halfway', (
    tester,
  ) async {
    await pumpFlow(tester, [OnboardingStep.welcome, OnboardingStep.profile]);

    await tester.tap(find.text('Get started'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    final fade = tester
        .widgetList<Opacity>(
          find.ancestor(of: find.text('Skip'), matching: find.byType(Opacity)),
        )
        .first;
    expect(fade.opacity, greaterThan(0));
    expect(fade.opacity, lessThan(1));
    expect(skip(), findsNothing);

    await tester.pumpAndSettle();
    expect(skip(), findsOneWidget);
  });

  testWidgets('Skip comes back on a step that asks for something, with the '
      'page where it was', (tester) async {
    await pumpFlow(tester, [OnboardingStep.welcome, OnboardingStep.profile]);
    final pagesTop = tester.getTopLeft(find.byType(PageView)).dy;

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(skip(), findsOneWidget);
    expect(tester.getTopLeft(find.byType(PageView)).dy, pagesTop);
  });

  testWidgets('a step that finishes after it was skipped never moves the '
      'next one on', (tester) async {
    final saved = Completer<void>();
    final client =
        buildTestClient(
            userId: _userId,
            httpClient: MockClient((_) async {
              await saved.future;
              return http.Response('{}', 200);
            }),
          )
          ..baseUri = Uri.parse('https://example.org')
          ..bearerToken = 'token';
    final store = await pumpFlow(tester, [
      OnboardingStep.profile,
      OnboardingStep.setUpRecovery,
      OnboardingStep.confirmPeople,
    ], client: client);

    await tester.enterText(find.byType(TextField), 'Alex');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.tap(skip());
    await tester.pumpAndSettle();
    expect(find.text('Set up recovery'), findsWidgets);

    saved.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set up recovery'), findsWidgets);
    expect(store.shown(_userId), {OnboardingStep.profile});
  });

  testWidgets('a single-step flow keeps Skip but shows no progress dots', (
    tester,
  ) async {
    await pumpFlow(tester, [OnboardingStep.profile]);

    expect(skip(), findsOneWidget);
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

    final skipCentre = tester.getCenter(skip());
    final dots = tester.getCenter(find.byKey(onboardingDotsKey));
    final button = tester.getRect(find.byType(FilledButton));
    final size = tester.getSize(find.byType(Scaffold).last);
    expect(skipCentre.dx, greaterThan(size.width / 2));
    expect(skipCentre.dy, lessThan(size.height / 4));
    expect(dots.dx, closeTo(size.width / 2, 1));
    expect(dots.dy, greaterThan(button.bottom));
    expect(
      tester.getTopLeft(find.byType(StepHero)).dy,
      greaterThan(skipCentre.dy),
    );
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
      if (i < 2) await moveOn(tester);
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
    stubNotificationPermission(granted: true);
    for (final step in OnboardingStep.values) {
      await tester.pumpWidget(const SizedBox());
      await pumpFlow(tester, [step]);
      final width = tester.getSize(find.byType(Scaffold).last).width;
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

    void stubBatteryCheck(Future<bool> Function() answer) {
      const channel = MethodChannel('zuno/background_sync');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'isIgnoringBatteryOptimizations') return null;
        return answer();
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }

    Future<void> pick(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pump();
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

    testWidgets('a second tap on Continue never skips the step after it', (
      tester,
    ) async {
      stubBatteryCheck(
        () => Future.delayed(const Duration(milliseconds: 200), () => true),
      );
      final store = await pumpFlow(tester, [
        OnboardingStep.deliveryMethod,
        OnboardingStep.confirmPeople,
      ]);

      await tester.tap(find.text('UnifiedPush'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(find.text('Continue'), warnIfMissed: false);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();

      expect(find.text('Make sure it is really them'), findsOneWidget);
      expect(store.shown(_userId), {OnboardingStep.deliveryMethod});
    });

    testWidgets('the methods stay put while the choice is being saved', (
      tester,
    ) async {
      stubBatteryCheck(
        () => Future.delayed(const Duration(milliseconds: 500), () => true),
      );
      await pumpFlow(tester, [
        OnboardingStep.deliveryMethod,
        OnboardingStep.confirmPeople,
      ]);

      await tester.tap(find.text('UnifiedPush'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.ensureVisible(find.text('Background sync'));
      await tester.pump();
      await tester.tap(find.text('Background sync'), warnIfMissed: false);
      await tester.pump();

      expect(
        tester
            .widget<RadioGroup<NotificationDeliveryMode>>(
              find.byType(RadioGroup<NotificationDeliveryMode>),
            )
            .groupValue,
        NotificationDeliveryMode.unifiedPush,
      );

      await tester.pumpAndSettle();
      expect(
        prefs.getString('settings.notification_delivery_mode'),
        'unifiedPush',
      );
    });

    testWidgets('a battery check that never answers still moves on', (
      tester,
    ) async {
      stubBatteryCheck(() => Completer<bool>().future);
      await pumpFlow(tester, [
        OnboardingStep.deliveryMethod,
        OnboardingStep.confirmPeople,
      ]);

      await tester.tap(find.text('UnifiedPush'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(find.text('Make sure it is really them'), findsOneWidget);
    });

    testWidgets('a method that needs it skips the battery step when Android '
        'already exempts the app', (tester) async {
      stubBatteryExemption(granted: true);
      await pumpFlow(tester, [
        OnboardingStep.deliveryMethod,
        OnboardingStep.setUpRecovery,
      ]);

      await pick(tester, 'Background sync');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Set up recovery'), findsOneWidget);
      expect(
        prefs.getString('settings.notification_delivery_mode'),
        'backgroundService',
      );
    });

    testWidgets('Android offers its three methods and nothing else', (
      tester,
    ) async {
      await pumpFlow(tester, [OnboardingStep.deliveryMethod]);

      expect(
        find.byType(RadioListTile<NotificationDeliveryMode>),
        findsNWidgets(3),
      );
      expect(find.text('Apple push'), findsNothing);
    });

    testWidgets('lists only the methods this platform has', (tester) async {
      await pumpFlow(
        tester,
        [OnboardingStep.deliveryMethod],
        capabilities: capabilitiesLike(
          androidCapabilities,
          deliveryModes: const [
            NotificationDeliveryMode.fcm,
            NotificationDeliveryMode.backgroundService,
          ],
        ),
      );

      expect(
        find.byType(RadioListTile<NotificationDeliveryMode>),
        findsNWidgets(2),
      );
      expect(find.text('UnifiedPush'), findsNothing);
    });

    testWidgets('a platform without a battery exemption never adds the '
        'battery step', (tester) async {
      stubBatteryExemption(granted: false);
      await pumpFlow(
        tester,
        [OnboardingStep.deliveryMethod, OnboardingStep.setUpRecovery],
        capabilities: capabilitiesLike(
          androidCapabilities,
          batteryExemption: false,
        ),
      );

      await tester.tap(find.text('UnifiedPush'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Let Zuno wake up'), findsNothing);
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

    NotificationDeliveryMode? preselected(WidgetTester tester) => tester
        .widget<RadioGroup<NotificationDeliveryMode>>(
          find.byType(RadioGroup<NotificationDeliveryMode>),
        )
        .groupValue;

    RadioListTile<NotificationDeliveryMode> option(
      WidgetTester tester,
      String label,
    ) => tester.widget<RadioListTile<NotificationDeliveryMode>>(
      find.widgetWithText(RadioListTile<NotificationDeliveryMode>, label),
    );

    NotificationDeliveryModeNotifier deliveryModes(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byType(OnboardingFlowPage)),
        ).read(notificationDeliveryModeProvider.notifier);

    for (final (fcm, reason) in [
      (
        FcmAvailability.unavailable,
        'This device does not have Google Play services.',
      ),
      (
        FcmAvailability.disabled,
        'Google Play services is turned off. Turn it on in your device '
            'settings to use this.',
      ),
      (
        FcmAvailability.notConfigured,
        'This version of Zuno does not include Google services.',
      ),
    ]) {
      testWidgets('${fcm.name}: Google services is listed with its reason '
          'but cannot be picked', (tester) async {
        await prefs.setString(
          'settings.notification_delivery_mode',
          NotificationDeliveryMode.unifiedPush.name,
        );
        await pumpFlow(tester, [
          OnboardingStep.deliveryMethod,
        ], fcm: AsyncData(fcm));

        expect(option(tester, 'Google services').enabled, isFalse);
        expect(find.text(reason), findsOneWidget);
        expect(option(tester, 'UnifiedPush').enabled, isTrue);

        await pick(tester, 'Google services');

        expect(preselected(tester), NotificationDeliveryMode.unifiedPush);
      });
    }

    testWidgets('a device that needs an update can pick Google services and '
        'is told what comes next', (tester) async {
      stubBatteryExemption(granted: true);
      await prefs.setString(
        'settings.notification_delivery_mode',
        NotificationDeliveryMode.backgroundService.name,
      );
      await pumpFlow(tester, [
        OnboardingStep.deliveryMethod,
        OnboardingStep.setUpRecovery,
      ], fcm: const AsyncData(FcmAvailability.updateRequired));

      expect(
        find.text(
          'Google Play services needs an update. Zuno offers the update once '
          'you choose this.',
        ),
        findsOneWidget,
      );
      await pick(tester, 'Google services');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(prefs.getString('settings.notification_delivery_mode'), 'fcm');
      expect(find.text('Set up recovery'), findsOneWidget);
    });

    group('while Zuno switches the method on its own', () {
      testWidgets('the step follows the switch, and Continue keeps it '
          'without recording a choice', (tester) async {
        stubBatteryExemption(granted: true);
        final store = await pumpFlow(tester, [
          OnboardingStep.deliveryMethod,
          OnboardingStep.setUpRecovery,
        ]);
        expect(preselected(tester), NotificationDeliveryMode.fcm);

        await deliveryModes(tester)
            .autoSelect(NotificationDeliveryMode.unifiedPush);
        await tester.pump();

        expect(preselected(tester), NotificationDeliveryMode.unifiedPush);

        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(find.text('Set up recovery'), findsOneWidget);
        expect(store.shown(_userId), {OnboardingStep.deliveryMethod});
        expect(
          prefs.getString('settings.notification_delivery_mode'),
          'unifiedPush',
        );
        expect(
          prefs.getBool('settings.notification_delivery_mode_chosen'),
          isNull,
        );
        expect(
          prefs.getString('settings.notification_delivery_mode_auto'),
          'unifiedPush',
        );
      });

      testWidgets('a method the person picked stays picked, and Continue '
          'saves it', (tester) async {
        stubBatteryExemption(granted: true);
        await pumpFlow(tester, [
          OnboardingStep.deliveryMethod,
          OnboardingStep.setUpRecovery,
        ]);

        await pick(tester, 'Background sync');
        await deliveryModes(tester)
            .autoSelect(NotificationDeliveryMode.unifiedPush);
        await tester.pump();

        expect(preselected(tester), NotificationDeliveryMode.backgroundService);

        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(
          prefs.getString('settings.notification_delivery_mode'),
          'backgroundService',
        );
        expect(
          prefs.getBool('settings.notification_delivery_mode_chosen'),
          isTrue,
        );
      });

      testWidgets('a pick of Google services that stops working falls back '
          'to the current method', (tester) async {
        stubBatteryExemption(granted: true);
        await prefs.setString(
          'settings.notification_delivery_mode',
          NotificationDeliveryMode.backgroundService.name,
        );
        await pumpFlow(tester, [
          OnboardingStep.deliveryMethod,
          OnboardingStep.setUpRecovery,
        ]);
        await pick(tester, 'Google services');
        expect(preselected(tester), NotificationDeliveryMode.fcm);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(OnboardingFlowPage)),
        );
        container.updateOverrides([
          sharedPreferencesProvider.overrideWithValue(prefs),
          matrixClientProvider.overrideWithValue(
            container.read(matrixClientProvider),
          ),
          fcmAvailabilityProvider.overrideWithValue(
            const AsyncData(FcmAvailability.disabled),
          ),
        ]);
        await tester.pump();

        expect(preselected(tester), NotificationDeliveryMode.backgroundService);

        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(
          prefs.getString('settings.notification_delivery_mode'),
          'backgroundService',
        );
        expect(
          prefs.getBool('settings.notification_delivery_mode_chosen'),
          isNull,
        );
      });
    });
  });

  group('with notifications off', () {
    const flow = [
      OnboardingStep.notifications,
      OnboardingStep.deliveryMethod,
      OnboardingStep.batteryExemption,
      OnboardingStep.autostart,
      OnboardingStep.setUpRecovery,
    ];

    testWidgets('skipping the permission drops every delivery step, for '
        'good', (tester) async {
      stubNotificationPermission(granted: false);
      final store = await pumpFlow(tester, flow);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('Set up recovery'), findsOneWidget);
      expect(find.text('How should messages reach you?'), findsNothing);
      expect(store.shown(_userId), {
        OnboardingStep.notifications,
        OnboardingStep.deliveryMethod,
        OnboardingStep.batteryExemption,
        OnboardingStep.autostart,
      });
    });

    testWidgets('declining the permission drops them too', (tester) async {
      stubNotificationPermission(granted: false);
      await pumpFlow(tester, flow);

      await tester.tap(find.text('Turn on notifications'));
      await tester.pumpAndSettle();

      expect(find.text('Set up recovery'), findsOneWidget);
    });

    testWidgets('a flow that ends at the permission closes', (tester) async {
      stubNotificationPermission(granted: false);
      await pumpFlow(tester, const [
        OnboardingStep.notifications,
        OnboardingStep.deliveryMethod,
      ]);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('with the permission granted, delivery comes next', (
      tester,
    ) async {
      stubNotificationPermission(granted: true);
      final store = await pumpFlow(tester, flow);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('How should messages reach you?'), findsOneWidget);
      expect(store.shown(_userId), {OnboardingStep.notifications});
    });
  });

  testWidgets('every step is one page with one primary button', (tester) async {
    stubNotificationPermission(granted: true);
    for (final step in OnboardingStep.values) {
      await tester.pumpWidget(const SizedBox());
      await pumpFlow(tester, [step]);

      expect(find.byType(FilledButton), findsOneWidget, reason: '$step');
      expect(
        skip(),
        offersSkip(step) ? findsOneWidget : findsNothing,
        reason: '$step',
      );
      if (offersSkip(step)) {
        await tester.tap(skip());
        await tester.pumpAndSettle();
        expect(find.text('open'), findsOneWidget, reason: '$step');
      }
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

  void recordChannel(String name, [Object? Function(MethodCall call)? answer]) {
    final channel = MethodChannel(name);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      channelCalls.add(call.method);
      return answer?.call(call);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  Future<void> useMode(NotificationDeliveryMode mode) =>
      prefs.setString('settings.notification_delivery_mode', mode.name);

  Future<void> resume(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
  }

  group('the photo on the name step', () {
    late _FakeImagePicker picker;

    setUp(() {
      picker = _FakeImagePicker();
      final original = ImagePickerPlatform.instance;
      ImagePickerPlatform.instance = picker;
      addTearDown(() => ImagePickerPlatform.instance = original);
    });

    testWidgets('a picked photo fills the circle and saves on its own', (
      tester,
    ) async {
      picker.answer = XFile.fromData(
        img.encodeJpg(img.Image(width: 800, height: 400)),
        path: 'IMG_0001.jpg',
        mimeType: 'image/jpeg',
      );
      final requests = <http.Request>[];
      final client = buildTestClient(
        userId: _userId,
        database: _UploadingDatabaseApi(),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({'content_uri': 'mxc://example.org/me'}),
            200,
          );
        }),
      );
      client.baseUri = Uri.parse('https://example.org');
      client.bearerToken = 'test-token';
      final store = await pumpFlow(tester, [
        OnboardingStep.profile,
      ], client: client);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      await tester.tap(find.byType(StepHero));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Change photo'), findsOneWidget);
      expect(tester.widget<StepHero>(find.byType(StepHero)).image, isNotNull);

      await tester.tap(find.text('Save'));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(requests.map((r) => r.url.pathSegments.last), [
        'upload',
        'avatar_url',
      ]);
      expect(store.shown(_userId), {OnboardingStep.profile});
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('a photo that cannot be picked says so and keeps the step', (
      tester,
    ) async {
      picker.error = PlatformException(code: 'photo_access_denied');
      await pumpFlow(tester, [OnboardingStep.profile]);

      await tester.tap(find.byType(StepHero));
      await tester.pumpAndSettle();

      expect(
        find.text('Photo not added. You can add one later in Settings.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Add a photo'), findsOneWidget);
      expect(find.text('What should people call you?'), findsOneWidget);
    });

    testWidgets('a cancelled pick changes nothing', (tester) async {
      await pumpFlow(tester, [OnboardingStep.profile]);

      await tester.tap(find.byType(StepHero));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Add a photo'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('the notifications step', () {
    late bool fullScreenAllowed;

    setUp(() {
      fullScreenAllowed = true;
      recordChannel(
        'zuno/calls',
        (call) =>
            call.method == 'canUseFullScreenIntent' ? fullScreenAllowed : null,
      );
      recordChannel('zuno/background_sync');
    });

    testWidgets('asks to show messages and ring for calls', (tester) async {
      await pumpFlow(tester, [OnboardingStep.notifications]);

      expect(
        find.text(
          'Zuno needs your permission to show new messages and ring for '
          'calls.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('on iOS, where calls ring without it, asks for messages only '
        'and moves straight on', (tester) async {
      ambientCapabilities = iosCapabilities;
      stubNotificationPermission(granted: true);
      fullScreenAllowed = false;
      await pumpFlow(tester, [
        OnboardingStep.notifications,
        OnboardingStep.setUpRecovery,
      ], capabilities: iosCapabilities);

      expect(
        find.text('Zuno needs your permission to show new messages.'),
        findsOneWidget,
      );
      expect(find.textContaining('ring for calls'), findsNothing);

      await tester.tap(find.text('Turn on notifications'));
      await tester.pumpAndSettle();

      expect(find.text('Let calls take over the screen'), findsNothing);
      expect(find.text('Set up recovery'), findsOneWidget);
      expect(channelCalls, isNot(contains('canUseFullScreenIntent')));
    });

    testWidgets('moves on once allowed and calls may ring full screen', (
      tester,
    ) async {
      stubNotificationPermission(granted: true);
      await pumpFlow(tester, [
        OnboardingStep.notifications,
        OnboardingStep.setUpRecovery,
      ]);

      await tester.tap(find.text('Turn on notifications'));
      await tester.pumpAndSettle();

      expect(channelCalls, contains('canUseFullScreenIntent'));
      expect(find.text('Set up recovery'), findsOneWidget);
    });

    testWidgets('asks for full-screen calls next, and moves on once they are '
        'allowed', (tester) async {
      stubNotificationPermission(granted: true);
      fullScreenAllowed = false;
      await pumpFlow(tester, [
        OnboardingStep.notifications,
        OnboardingStep.setUpRecovery,
      ]);

      await tester.tap(find.text('Turn on notifications'));
      await tester.pumpAndSettle();

      expect(find.text('Let calls take over the screen'), findsOneWidget);
      await tester.tap(find.text('Open settings'));
      await tester.pump();
      expect(channelCalls, contains('openFullScreenIntentSettings'));

      await resume(tester);
      expect(find.text('Let calls take over the screen'), findsOneWidget);

      fullScreenAllowed = true;
      await resume(tester);
      expect(find.text('Set up recovery'), findsOneWidget);
    });

    testWidgets('restarts background sync when it is the delivery method', (
      tester,
    ) async {
      await useMode(NotificationDeliveryMode.backgroundService);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const permissions = MethodChannel(
        'flutter.baseflow.com/permissions/methods',
      );
      var granted = false;
      messenger.setMockMethodCallHandler(
        permissions,
        (call) async => switch (call.method) {
          'checkPermissionStatus' => granted ? 1 : 0,
          'requestPermissions' => {17: (granted = true) ? 1 : 0},
          _ => null,
        },
      );
      addTearDown(() => messenger.setMockMethodCallHandler(permissions, null));
      await pumpFlow(tester, [
        OnboardingStep.notifications,
        OnboardingStep.setUpRecovery,
      ]);

      await tester.tap(find.text('Turn on notifications'));
      await tester.pumpAndSettle();

      expect(channelCalls, contains('startBackgroundSyncService'));
    });
  });

  group('the battery step', () {
    late bool exempt;

    setUp(() {
      exempt = false;
      recordChannel(
        'zuno/background_sync',
        (call) => switch (call.method) {
          'isIgnoringBatteryOptimizations' => exempt,
          'isPackageIgnoringBatteryOptimizations' => true,
          _ => null,
        },
      );
    });

    testWidgets('Allow asks Android, and returning exempt moves on', (
      tester,
    ) async {
      await useMode(NotificationDeliveryMode.backgroundService);
      await pumpFlow(tester, [
        OnboardingStep.batteryExemption,
        OnboardingStep.setUpRecovery,
      ]);

      await tester.tap(find.text('Allow'));
      await tester.pump();
      expect(channelCalls, contains('requestIgnoreBatteryOptimizations'));

      await resume(tester);
      expect(find.text('Let Zuno wake up'), findsOneWidget);

      exempt = true;
      await resume(tester);
      expect(find.text('Set up recovery'), findsOneWidget);
    });

    group('with UnifiedPush', () {
      setUp(() {
        final platform = UnifiedPushPlatform.instance;
        UnifiedPushPlatform.instance = FakeUnifiedPush();
        final check =
            unifiedPushDeliveryProvider.distributorIgnoresBatteryOptimizations;
        addTearDown(() {
          UnifiedPushPlatform.instance = platform;
          unifiedPushDeliveryProvider
            ..distributorIgnoresBatteryOptimizations = check
            ..savedDistributor = null
            ..distributorBatteryRestricted.value = false;
        });
      });

      testWidgets('a sleeping distributor gets its own note and button', (
        tester,
      ) async {
        await useMode(NotificationDeliveryMode.unifiedPush);
        unifiedPushDeliveryProvider
          ..savedDistributor = 'io.heckel.ntfy'
          ..distributorIgnoresBatteryOptimizations = (_) async => false;
        await pumpFlow(tester, [OnboardingStep.batteryExemption]);

        expect(find.textContaining('ntfy delivers notifications'), findsOne);
        await tester.tap(find.text('Open ntfy settings'));
        await tester.pump();

        expect(channelCalls, contains('openAppSettings'));
      });

      testWidgets('an awake distributor gets no note', (tester) async {
        await useMode(NotificationDeliveryMode.unifiedPush);
        unifiedPushDeliveryProvider
          ..savedDistributor = 'io.heckel.ntfy'
          ..distributorIgnoresBatteryOptimizations = (_) async => true;
        await pumpFlow(tester, [OnboardingStep.batteryExemption]);

        expect(find.textContaining('delivers notifications'), findsNothing);
      });
    });
  });

  testWidgets('the autostart step opens the setting and moves on', (
    tester,
  ) async {
    recordChannel('zuno/background_sync');
    await pumpFlow(tester, [
      OnboardingStep.autostart,
      OnboardingStep.setUpRecovery,
    ]);

    expect(find.text('Let Zuno start on its own'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    expect(channelCalls, ['openAutostartSettings']);
    expect(find.text('Set up recovery'), findsOneWidget);
  });

  group('the security steps', () {
    testWidgets('a locked device opens the unlock page, then moves on', (
      tester,
    ) async {
      final store = await pumpFlow(tester, [OnboardingStep.approveDevice]);

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      final page = tester.widget<ApproveThisDevicePage>(
        find.byType(ApproveThisDevicePage),
      );
      expect(page.showStartOver, isTrue);

      Navigator.of(tester.element(find.byType(ApproveThisDevicePage))).pop();
      await tester.pumpAndSettle();

      expect(store.shown(_userId), {OnboardingStep.approveDevice});
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets(
      'as the last step, its page is fully gone before the flow '
      'leaves forward',
      (tester) async {
        final store = await pumpFlow(tester, [
          OnboardingStep.approveDevice,
        ], forwardExit: true);
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        Navigator.of(tester.element(find.byType(ApproveThisDevicePage))).pop();
        final lefts = <double>[];
        for (var frame = 0; frame < 60; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final flow = find.byType(OnboardingFlowPage, skipOffstage: false);
          if (flow.evaluate().isNotEmpty) lefts.add(tester.getTopLeft(flow).dx);
        }

        expect(lefts.where((dx) => dx > 1), isEmpty);
        expect(lefts.last, lessThan(-400));
        await tester.pumpAndSettle();
        expect(find.text('open'), findsOneWidget);
        expect(store.shown(_userId), {OnboardingStep.approveDevice});
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );

    testWidgets('recovery opens its setup and starts the cooldown', (
      tester,
    ) async {
      final store = await pumpFlow(tester, [
        OnboardingStep.setUpRecovery,
      ], client: EncryptedTestClient(userId: _userId));

      await tester.tap(find.widgetWithText(FilledButton, 'Set up recovery'));
      await tester.pumpAndSettle();

      expect(find.byType(SecureBackupPage), findsOneWidget);
      expect(prefs.getInt('security.recovery_prompt_ms'), isNotNull);

      Navigator.of(tester.element(find.byType(SecureBackupPage))).pop();
      await tester.pumpAndSettle();

      expect(store.shown(_userId), {OnboardingStep.setUpRecovery});
      expect(find.text('open'), findsOneWidget);
    });
  });
}
