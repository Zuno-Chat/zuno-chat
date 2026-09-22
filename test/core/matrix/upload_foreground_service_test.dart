import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/upload_foreground_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/upload_service');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late UploadForegroundService service;

  setUp(() {
    calls = [];
    service = UploadForegroundService.forTest();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  List<String> methods() => calls.map((c) => c.method).toList();

  test(
    'the first acquire starts the service, the last release stops it',
    () async {
      await service.acquire();
      await service.acquire();
      expect(methods(), ['start']);
      await service.release();
      expect(methods(), ['start']);
      await service.release();
      expect(methods(), ['start', 'stop']);
    },
  );

  test('a release without a matching acquire does nothing', () async {
    await service.release();
    expect(calls, isEmpty);
    await service.acquire();
    expect(methods(), ['start']);
  });

  test('progress posts the label and a whole percent', () async {
    await service.acquire();
    await service.updateProgress(label: 'Uploading photo…', fraction: 0.256);
    expect(calls.last.method, 'update');
    expect(calls.last.arguments, {'label': 'Uploading photo…', 'percent': 26});
  });

  test('an unknown fraction posts a null percent', () async {
    await service.acquire();
    await service.updateProgress(label: 'Compressing video…', fraction: null);
    expect(calls.last.arguments, {
      'label': 'Compressing video…',
      'percent': null,
    });
  });

  test('repeats of the same label and percent are not re-sent', () async {
    await service.acquire();
    await service.updateProgress(label: 'Uploading…', fraction: 0.101);
    await service.updateProgress(label: 'Uploading…', fraction: 0.104);
    await service.updateProgress(label: 'Uploading…', fraction: 0.11);
    expect(methods(), ['start', 'update', 'update']);
  });

  test('progress is dropped while nothing holds the service', () async {
    await service.updateProgress(label: 'Uploading…', fraction: 0.5);
    expect(calls, isEmpty);
  });

  test('a fresh hold forgets the previous send\'s last progress', () async {
    await service.acquire();
    await service.updateProgress(label: 'Uploading…', fraction: 0.5);
    await service.release();
    await service.acquire();
    await service.updateProgress(label: 'Uploading…', fraction: 0.5);
    expect(methods(), ['start', 'update', 'stop', 'start', 'update']);
  });

  test(
    'a native failure is swallowed and the hold count still moves',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'unavailable');
      });
      await service.acquire();
      await service.updateProgress(label: 'Uploading…', fraction: 0.5);
      await service.release();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      await service.acquire();
      expect(methods(), ['start']);
    },
  );
}
