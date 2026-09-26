import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/features/calls/presentation/call_page.dart';

import '../../../helpers/platform_capabilities.dart';
import 'call_page_harness.dart';

void main() {
  FakeCallSession callerSession() => FakeCallSession(
    room: CallPageHarness.buildRoom(),
    kind: CallKind.voice,
    role: CallSessionRole.caller,
  );

  testWidgets('android runs the call in its service and plays ringback to '
      'the caller', (tester) async {
    final harness = CallPageHarness(tester, capabilities: androidCapabilities);
    final session = callerSession();
    await harness.open(session);

    expect(harness.count('startCallForegroundService'), 1);
    expect(harness.ringbackPlaying, isTrue);

    session.end();
    await harness.settle();

    expect(find.byType(CallPage), findsNothing);
    expect(harness.count('stopCallForegroundService'), 1);
    expect(harness.ringbackPlaying, isFalse);
  });

  testWidgets('without a call service or a native ringback the call still '
      'runs and ends, and neither is asked for', (tester) async {
    final harness = CallPageHarness(tester, capabilities: iosCapabilities);
    final session = callerSession();
    await harness.open(session);

    expect(find.byType(CallPage), findsOneWidget);
    expect(harness.audioRoute, 'earpiece');

    session.end();
    await harness.settle();

    expect(find.byType(CallPage), findsNothing);
    expect(harness.count('startCallForegroundService'), 0);
    expect(harness.count('stopCallForegroundService'), 0);
    expect(harness.count('startRingbackTone'), 0);
    expect(harness.count('stopRingbackTone'), 0);
  });
}
