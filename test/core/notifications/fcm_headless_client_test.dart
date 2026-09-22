import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/push/fcm_background_handler.dart';
import 'package:zuno/core/push/headless_push_runner.dart';

import '../../helpers/fake_matrix.dart';

class _RecordingClient extends Client {
  _RecordingClient() : super('test', database: FakeDatabaseApi());

  int disposeCalls = 0;
  bool? closedDatabase;
  int resolveCalls = 0;

  @override
  Future<Event?> getEventByPushNotification(
    PushNotification notification, {
    bool storeInDatabase = true,
    Duration timeoutForServerRequests = const Duration(seconds: 8),
    bool returnNullIfSeen = true,
  }) async {
    resolveCalls++;
    return null;
  }

  @override
  Future<void> dispose({bool closeDatabase = true}) async {
    disposeCalls++;
    closedDatabase = closeDatabase;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('opens and disposes one client per push', () async {
    final built = <_RecordingClient>[];
    final runner = HeadlessPushRunner()
      ..clientBuilder = () async {
        final client = _RecordingClient();
        built.add(client);
        return client;
      };

    await handleFcmMessage(runner, {
      'event_id': '\$one',
      'room_id': '!room:example.org',
    });
    await handleFcmMessage(runner, {
      'event_id': '\$two',
      'room_id': '!room:example.org',
    });

    expect(built, hasLength(2));
    expect(built.every((c) => c.resolveCalls == 1), isTrue);
    expect(built.every((c) => c.disposeCalls == 1), isTrue);
    expect(built.every((c) => c.closedDatabase == false), isTrue);
  });

  test('opens no client at all for a payload with no event', () async {
    var builds = 0;
    final runner = HeadlessPushRunner()
      ..clientBuilder = () async {
        builds++;
        return _RecordingClient();
      };

    await handleFcmMessage(runner, {'room_id': '!room:example.org'});

    expect(builds, 0);
  });

  test('a malformed payload is dropped without throwing', () async {
    final runner = HeadlessPushRunner()
      ..clientBuilder = () async => _RecordingClient();

    await handleFcmMessage(runner, const {});
  });
}
