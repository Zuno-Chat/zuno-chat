import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _toggleChannel =
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';

class _ToggleCodec extends StandardMessageCodec {
  const _ToggleCodec();

  @override
  Object? readValueOfType(int type, ReadBuffer buffer) => type == 129
      ? (readValue(buffer)! as List<Object?>).single
      : super.readValueOfType(type, buffer);
}

class FakeScreenAwake {
  final toggles = <bool>[];
  bool refuses = false;
}

FakeScreenAwake installFakeScreenAwake() {
  final screen = FakeScreenAwake();
  const codec = _ToggleCodec();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(_toggleChannel, (message) async {
        final args = codec.decodeMessage(message)! as List<Object?>;
        screen.toggles.add(args.single! as bool);
        return codec.encodeMessage(
          screen.refuses
              ? <Object?>['wakelock-refused', null, null]
              : <Object?>[null],
        );
      });
  return screen;
}
