import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/features/calls/presentation/call_page.dart';

import 'call_page_harness.dart';

void main() {
  Future<FakeCallSession> talking(
    CallPageHarness harness, {
    CallKind kind = CallKind.video,
    bool localCamera = false,
    bool remoteCamera = false,
  }) async {
    final session = FakeCallSession(
      room: CallPageHarness.buildRoom(),
      kind: kind,
    );
    await harness.open(session);
    session.engine.participants = [
      localParticipant(camera: localCamera),
      remoteParticipant(camera: remoteCamera),
    ];
    session.moveTo(CallSessionPhase.active);
    await harness.settle();
    return session;
  }

  int created(CallPageHarness harness) =>
      harness.webrtc.where((c) => c.method == 'createVideoRenderer').length;

  int disposed(CallPageHarness harness) =>
      harness.webrtc.where((c) => c.method == 'videoRendererDispose').length;

  List<String> sources(CallPageHarness harness, int texture) => [
    for (final call in harness.webrtc)
      if (call.method == 'videoRendererSetSrcObject' &&
          (call.arguments as Map)['textureId'] == texture)
        (call.arguments as Map)['streamId'] as String,
  ];

  testWidgets('a voice call creates no video renderers', (tester) async {
    final harness = CallPageHarness(tester);
    await talking(harness, kind: CallKind.voice);

    expect(created(harness), 0);
    await harness.close();
  });

  testWidgets('a camera turned on mid-call gets one renderer, kept while it '
      'is turned off and on again', (tester) async {
    final harness = CallPageHarness(tester);
    final session = await talking(harness);
    expect(created(harness), 0);

    session.engine.setParticipants([
      localParticipant(),
      remoteParticipant(camera: true),
    ]);
    await harness.settle();
    session.engine.setParticipants([localParticipant(), remoteParticipant()]);
    await harness.settle();
    session.engine.setParticipants([
      localParticipant(),
      remoteParticipant(camera: true),
    ]);
    await harness.settle();

    expect(created(harness), 1);
    expect(disposed(harness), 0);
    await harness.close();
  });

  testWidgets('minimized, only the video the window shows stays attached; '
      'reopened, every camera comes back', (tester) async {
    final harness = CallPageHarness(tester);
    await talking(harness, localCamera: true, remoteCamera: true);
    harness.webrtc.clear();

    await harness.minimize();

    expect(sources(harness, 1), ['']);
    expect(sources(harness, 2), isEmpty);

    harness.webrtc.clear();
    showCallScreen(harness.navigatorKey.currentState!, harness.call);
    await harness.settle();

    expect(sources(harness, 1), ['local-video']);
    expect(sources(harness, 2), isEmpty);
    await harness.close();
  });

  testWidgets('a call minimized to the bar shows no video at all', (
    tester,
  ) async {
    final harness = CallPageHarness(tester);
    await talking(harness, localCamera: true);
    harness.webrtc.clear();

    await harness.minimize();

    expect(sources(harness, 1), ['']);
    await harness.close();
  });

  testWidgets('a video that cannot be set up leaves that person on their '
      'picture and the call going, and the next update tries again', (
    tester,
  ) async {
    final harness = CallPageHarness(tester)..rendererCreatesToRefuse = 1;
    final session = await talking(harness, remoteCamera: true);

    final remote = harness.call.remotes.single;
    expect(harness.call.rendererFor(remote.id), isNull);
    expect(harness.call.talkingSince, isNotNull);

    session.engine.setParticipants([
      localParticipant(),
      remoteParticipant(camera: true),
    ]);
    await harness.settle();

    expect(harness.call.rendererFor(remote.id), isNotNull);
    await harness.close();
  });
}
