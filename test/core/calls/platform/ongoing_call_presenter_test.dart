import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/platform/ongoing_call_presenter.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/calls');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  });

  test('android runs the call in its foreground service', () async {
    final presenter = ongoingCallPresenterFor(androidCapabilities);

    await presenter.start(title: 'Weekend hike', withCamera: true);
    await presenter.stop();

    expect(presenter, isA<AndroidOngoingCallPresenter>());
    expect(calls.map((c) => [c.method, c.arguments]), [
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

  test('a missing platform side is not an error', () async {
    messenger.setMockMethodCallHandler(channel, null);
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
    expect(calls, isEmpty);
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
