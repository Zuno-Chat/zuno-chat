import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide CallSession;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/active_call_controller.dart';
import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/errors/global_error_handler.dart';
import 'package:zuno/core/navigation/global_navigator.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/calls/presentation/call_layer.dart';
import 'package:zuno/features/calls/presentation/call_page.dart';

import '../../../helpers/call_channel_mocks.dart';
import '../../../helpers/fake_call_session.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/pump_until.dart';

export '../../../helpers/call_channel_mocks.dart';
export '../../../helpers/fake_call_session.dart';

class CallPageHarness extends CallChannelMocks {
  CallPageHarness(
    this.tester, {
    PlatformCapabilities? capabilities,
    List<Override> overrides = const [],
    this.topBanner,
    this.home = const Scaffold(body: Text('Chat')),
  }) {
    SharedPreferences.setMockInitialValues({});
    installFakeLocalNotifications();
    silenceMethodChannels(const ['zuno/vibration']);
    container = ProviderContainer(
      overrides: [
        if (capabilities != null)
          platformCapabilitiesProvider.overrideWithValue(capabilities),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    addTearDown(
      () => CallNotificationService.instance.inPictureInPicture.value = false,
    );
  }

  final WidgetTester tester;
  final Widget? topBanner;
  final Widget home;
  late final ProviderContainer container;
  final navigatorKey = globalNavigatorKey;

  ActiveCallController get call =>
      container.read(activeCallControllerProvider)!;

  static Room buildRoom() => buildCallRoom();

  Future<void> open(FakeCallSession session) async {
    await showChat();
    pushCall(session);
    await settle();
  }

  Future<void> showChat() async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: zunoLightTheme,
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: globalScaffoldMessengerKey,
          builder: (context, child) => CallLayer(
            banners: [topBanner],
            child: child ?? const SizedBox.shrink(),
          ),
          home: home,
        ),
      ),
    );
  }

  void pushCall(FakeCallSession session) {
    container.read(activeCallProvider.notifier).set(session);
    showCallScreen(navigatorKey.currentState!, call);
  }

  Future<void> minimize() async {
    await tester.tap(find.byTooltip('Minimize call'));
    await settle();
  }

  Future<void> settle() async {
    await pumpRealAsync(
      tester,
      rounds: 5,
      step: const Duration(milliseconds: 100),
    );
  }

  Future<void> close() async {
    container.read(activeCallControllerProvider)?.close();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> changeHeadsets(List<String> connected) async {
    await reportHeadsets(connected);
    await settle();
  }

  Finder get speakerButton => find.byWidgetPredicate(
    (w) =>
        w is Tooltip &&
        (w.message == 'Turn speaker on' || w.message == 'Turn speaker off'),
  );

  IconData? get speakerIcon => tester
      .widget<Icon>(
        find.descendant(of: speakerButton, matching: find.byType(Icon)),
      )
      .icon;
}
