import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/unified_push_delivery_provider.dart';
import 'package:zuno/core/push/unified_push_headless_entry.dart';

import '../../helpers/fake_matrix.dart';

class _RecordingClient extends Client {
  _RecordingClient() : super('test', database: FakeDatabaseApi());

  @override
  Future<void> dispose({bool closeDatabase = true}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts the client build before the notification setup finishes, '
      'with the callbacks already registered', () async {
    final setup = Completer<void>();
    var builds = 0;
    final provider = UnifiedPushDeliveryProvider();

    final done = runUnifiedPushHeadless(
      provider: provider,
      clientBuilder: () async {
        builds++;
        return _RecordingClient();
      },
      initializeNotifications: () => setup.future,
      firstCallbackTimeout: const Duration(milliseconds: 20),
    );
    await pumpEventQueue();
    final buildsBeforeSetupFinished = builds;
    setup.complete();
    await done;

    expect(buildsBeforeSetupFinished, 1);
    expect(provider.runner.clientBuilder, isNotNull);
    expect(provider.runner.onPushHandled, isNotNull);
  });

  test('a failed notification setup still leaves the handler waiting for '
      'the push instead of crashing the engine', () async {
    final provider = UnifiedPushDeliveryProvider();

    await runUnifiedPushHeadless(
      provider: provider,
      clientBuilder: () async => _RecordingClient(),
      initializeNotifications: () async => throw StateError('no channel'),
      firstCallbackTimeout: const Duration(milliseconds: 20),
    );

    expect(provider.runner.clientBuilder, isNotNull);
  });
}
