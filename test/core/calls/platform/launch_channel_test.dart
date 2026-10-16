import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/platform/launch_channel.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answerWakeReason(String reason) {
    messenger.setMockMethodCallHandler(
      launchChannel,
      (call) async => call.method == 'takeWakeReason' ? reason : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(launchChannel, null));
  }

  setUp(() {
    ambientCapabilities = capabilitiesLike(iosCapabilities, voipRing: true);
  });

  test('reports why the app was woken, once', () async {
    answerWakeReason('ring');

    expect(await const LaunchChannel().takeWakeReason(), WakeReason.ring);
  });

  test('an unknown reason is no reason', () async {
    answerWakeReason('party');

    expect(await const LaunchChannel().takeWakeReason(), isNull);
  });

  test('without the plugin there is no reason', () async {
    expect(await const LaunchChannel().takeWakeReason(), isNull);
  });
}
