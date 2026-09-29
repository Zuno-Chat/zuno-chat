import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/platform_capabilities.dart';
import 'room_page_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/image_picker');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> picks;

  setUp(() {
    picks = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      picks.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  });

  Future<Map<Object?, Object?>> pickFrom(
    WidgetTester tester,
    RoomPageHarness harness,
    String option,
  ) async {
    harness.db.events = [harness.message(r'$m1')];
    await harness.pumpRoomPage(tester);
    await tester.tap(find.byIcon(Icons.attach_file_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(option));
    await harness.settle(tester);
    return picks.single.arguments as Map<Object?, Object?>;
  }

  testWidgets('without a native resizer, gallery photos arrive at the send '
      'size', (tester) async {
    final args = await pickFrom(
      tester,
      RoomPageHarness(
        capabilities: capabilitiesLike(
          iosCapabilities,
          nativeImageResize: false,
        ),
      ),
      'Choose from gallery',
    );

    expect(picks.single.method, 'pickMedia');
    expect(
      (args['maxImageWidth'], args['maxImageHeight'], args['imageQuality']),
      (720.0, 720.0, 75),
    );
  });

  testWidgets('without a native resizer, a camera photo arrives at the send '
      'size', (tester) async {
    final args = await pickFrom(
      tester,
      RoomPageHarness(
        capabilities: capabilitiesLike(
          iosCapabilities,
          nativeImageResize: false,
        ),
      ),
      'Take photo',
    );

    expect(picks.single.method, 'pickImage');
    expect(
      (args['maxWidth'], args['maxHeight'], args['imageQuality']),
      (720.0, 720.0, 75),
    );
  });

  testWidgets('with a native resizer the picker hands over the original', (
    tester,
  ) async {
    final args = await pickFrom(
      tester,
      RoomPageHarness(capabilities: androidCapabilities),
      'Choose from gallery',
    );

    expect(
      (args['maxImageWidth'], args['maxImageHeight'], args['imageQuality']),
      (null, null, null),
    );
  });

  testWidgets('on iOS the native resizer takes the original too', (
    tester,
  ) async {
    final args = await pickFrom(
      tester,
      RoomPageHarness(capabilities: iosCapabilities),
      'Choose from gallery',
    );

    expect(
      (args['maxImageWidth'], args['maxImageHeight'], args['imageQuality']),
      (null, null, null),
    );
  });
}
