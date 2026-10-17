import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/platform/ongoing_call_presenter.dart';
import 'package:zuno/core/notifications/settings/notification_preview.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordedMethodCalls native;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    native = installFakeCallsChannel();
  });

  test('android runs the call in its foreground service', () async {
    final presenter = ongoingCallPresenterFor(androidCapabilities);

    await presenter.start(title: 'Weekend hike', withCamera: true);
    await presenter.stop();

    expect(presenter, isA<AndroidOngoingCallPresenter>());
    expect(native.calls.map((c) => [c.method, c.arguments]), [
      [
        'startCallForegroundService',
        {
          'title': 'Weekend hike',
          'text': 'Tap to return to the call',
          'withCamera': true,
        },
      ],
      ['stopCallForegroundService', null],
    ]);
  });

  test(
    'at Nothing the ongoing call is a Zuno call, never the chat\'s name',
    () async {
      SharedPreferences.setMockInitialValues({
        notificationPreviewKey: NotificationPreview.nothing.name,
      });

      await const AndroidOngoingCallPresenter().start(
        title: 'Weekend hike',
        withCamera: false,
      );

      expect((native.calls.single.arguments as Map)['title'], 'Zuno call');
    },
  );

  test('at Name only the ongoing call keeps the chat\'s name', () async {
    SharedPreferences.setMockInitialValues({
      notificationPreviewKey: NotificationPreview.nameOnly.name,
    });

    await const AndroidOngoingCallPresenter().start(
      title: 'Weekend hike',
      withCamera: false,
    );

    expect((native.calls.single.arguments as Map)['title'], 'Weekend hike');
  });

  test('a start reaches the platform before the stop that follows it, '
      'however long the level takes to read', () async {
    const presenter = AndroidOngoingCallPresenter();

    final starting = presenter.start(title: 'Weekend hike', withCamera: false);
    final stopping = presenter.stop();
    await Future.wait<void>([starting, stopping]);

    expect(native.calls.map((c) => c.method), [
      'startCallForegroundService',
      'stopCallForegroundService',
    ]);
  });

  test('a missing platform side is not an error', () async {
    removeCallsChannel();
    const presenter = AndroidOngoingCallPresenter();

    await expectLater(
      presenter.start(title: 'Weekend hike', withCamera: false),
      completes,
    );
    await expectLater(presenter.stop(), completes);
  });

  test('a platform without a call service starts and stops nothing', () async {
    for (final capabilities in [
      iosCapabilities,
      capabilitiesLike(androidCapabilities, callForegroundService: false),
    ]) {
      final presenter = ongoingCallPresenterFor(capabilities);

      await presenter.start(title: 'Weekend hike', withCamera: true);
      await presenter.stop();

      expect(presenter, isA<NoopOngoingCallPresenter>());
    }
    expect(native.calls, isEmpty);
  });

  test('the provider follows the platform capabilities', () {
    final android = ProviderContainer();
    addTearDown(android.dispose);
    final ios = ProviderContainer(
      overrides: [
        platformCapabilitiesProvider.overrideWithValue(iosCapabilities),
      ],
    );
    addTearDown(ios.dispose);

    expect(
      android.read(ongoingCallPresenterProvider),
      isA<AndroidOngoingCallPresenter>(),
    );
    expect(
      ios.read(ongoingCallPresenterProvider),
      isA<NoopOngoingCallPresenter>(),
    );
  });
}
