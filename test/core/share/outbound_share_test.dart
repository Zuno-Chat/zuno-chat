import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/share/outbound_share.dart';

import '../../helpers/fake_attachments.dart';
import '../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DeviceFakes device;

  setUp(() => device = installDeviceFakes());

  final files = [
    XFile('/cache/handover/a/holiday.png', mimeType: 'image/png'),
    XFile('/cache/handover/b/notes'),
  ];

  test('on Android, files go out through Zuno itself', () async {
    await shareFiles(files, capabilities: androidCapabilities);

    expect(device.sharePlus, isEmpty);
    expect(device.nativeShares.single, {
      'paths': ['/cache/handover/a/holiday.png', '/cache/handover/b/notes'],
      'mimeTypes': ['image/png', null],
    });
  });

  test('on iOS, files go to the share sheet as they are', () async {
    await shareFiles(files, capabilities: iosCapabilities);

    expect(device.nativeShares, isEmpty);
    expect(device.sharePlus.single['paths'], [
      '/cache/handover/a/holiday.png',
      '/cache/handover/b/notes',
    ]);
  });

  test('a share Android refuses fails for the caller', () async {
    device.nativeShareError = PlatformException(code: 'share_failed');

    await expectLater(
      shareFiles(files, capabilities: androidCapabilities),
      throwsA(isA<PlatformException>()),
    );
  });
}
