import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/push_diagnostics.dart';

import '../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/push_diag');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('the raw snapshot keeps every key', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => {
        'settings': <String, Object?>{},
        'ledger': [
          {'state': 'missed', 'source': 'push', 'ts': 5},
        ],
      },
    );

    final raw = await PushDiagnostics(
      capabilities: capabilitiesLike(iosCapabilities, pushDiagnostics: true),
    ).rawSnapshot();

    expect((raw?['ledger'] as List?)?.length, 1);
  });

  test('without push diagnostics nothing is asked', () async {
    var asked = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      asked = true;
      return null;
    });

    expect(
      await PushDiagnostics(
        capabilities: capabilitiesLike(
          androidCapabilities,
          pushDiagnostics: false,
        ),
      ).rawSnapshot(),
      isNull,
    );
    expect(asked, isFalse);
  });

  test(
    'without the native handler there is no snapshot and nothing throws',
    () async {
      expect(
        await PushDiagnostics(
          capabilities: capabilitiesLike(
            iosCapabilities,
            pushDiagnostics: true,
          ),
        ).rawSnapshot(),
        isNull,
      );
    },
  );

  test('a native failure is no snapshot', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'unavailable'),
    );

    expect(
      await PushDiagnostics(
        capabilities: capabilitiesLike(iosCapabilities, pushDiagnostics: true),
      ).rawSnapshot(),
      isNull,
    );
  });
}
