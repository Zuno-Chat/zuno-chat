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
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/notifications/notification_delivery_provider.dart';
import 'package:zuno/core/onboarding/onboarding_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/security/security_prompt_provider.dart';
import 'package:zuno/core/onboarding/onboarding_step.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/core/ui/step_hero.dart';
import 'package:zuno/core/ui/step_layout.dart';
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
  }) async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        matrixClientProvider.overrideWithValue(
          client ?? buildTestClient(userId: _userId, httpClient: httpClient),
        ),
        if (capabilities != null)
          platformCapabilitiesProvider.overrideWithValue(capabilities),
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
    stubNotificationPermission(granted: true);
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
