import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/active_call_controller.dart';
import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/models/call_surface.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';

import '../../helpers/call_channel_mocks.dart';
import '../../helpers/fake_call_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FakeCallSession voiceCall() =>
      FakeCallSession(room: buildCallRoom(), kind: CallKind.voice);

  ProviderContainer containerWithControllers() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(activeCallControllerProvider);
    return container;
  }

  test('a call takes the ongoing-call notice as soon as it is set, with no '
      'frame drawn', () async {
    final mocks = CallChannelMocks();
    final container = containerWithControllers();

    container.read(activeCallProvider.notifier).set(voiceCall());
    await pumpEventQueue();

    expect(mocks.count('startCallForegroundService'), 1);
    expect(container.read(activeCallControllerProvider), isNotNull);
  });

  test('a call cleared before it ends gives back the notice it took', () async {
    final mocks = CallChannelMocks();
    final container = containerWithControllers();
    container.read(activeCallProvider.notifier).set(voiceCall());
    await pumpEventQueue();

    container.read(activeCallProvider.notifier).set(null);
    await pumpEventQueue();

    expect(mocks.count('stopCallForegroundService'), 1);
    expect(container.read(activeCallControllerProvider), isNull);
  });

  test('a call replaced by another leaves the new call its notice', () async {
    final mocks = CallChannelMocks();
    final container = containerWithControllers();
    final first = voiceCall();
    container.read(activeCallProvider.notifier).set(first);
    await pumpEventQueue();

    final second = voiceCall();
    container.read(activeCallProvider.notifier).set(second);
    await pumpEventQueue();

    expect(mocks.count('stopCallForegroundService'), 0);
    expect(container.read(activeCallControllerProvider)?.session, same(second));
  });

  test('a call that ends before it starts never undoes the next call\'s '
      'device state', () async {
    final mocks = CallChannelMocks();
    final container = containerWithControllers();

    container.read(activeCallProvider.notifier).set(voiceCall()..end());
    container.read(activeCallProvider.notifier).set(voiceCall());
    await pumpEventQueue();

    expect(mocks.count('startCallForegroundService'), 1);
    expect(mocks.count('stopCallForegroundService'), 0);
  });

  test('a call shows on one surface at a time: its screen, then '
      'picture-in-picture, a window while the other camera is on, otherwise '
      'the bar', () async {
    CallChannelMocks();
    final pictureInPicture =
        CallNotificationService.instance.inPictureInPicture;
    addTearDown(() => pictureInPicture.value = false);
    final container = containerWithControllers();
    final session = voiceCall();
    container.read(activeCallProvider.notifier).set(session);
    await pumpEventQueue();
    final call = container.read(activeCallControllerProvider)!;
    var notified = 0;
    call.addListener(() => notified++);

    expect(call.surface, CallSurface.bar);

    session.moveTo(CallSessionPhase.active);
    session.engine.setParticipants([
      localParticipant(),
      remoteParticipant(camera: true),
    ]);
    await pumpEventQueue();
    expect(call.surface, CallSurface.window);

    call.screenOpen = true;
    expect(call.surface, CallSurface.screen);

    notified = 0;
    pictureInPicture.value = true;
    expect(call.surface, CallSurface.pictureInPicture);
    expect(notified, greaterThan(0));

    pictureInPicture.value = false;
    session.end();
    await pumpEventQueue();
    expect(call.surface, CallSurface.none);
  });
}
