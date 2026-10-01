import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/push/fcm_bridge.dart';
import 'package:zuno/core/push/fcm_headless_entry.dart';
import 'package:zuno/core/push/headless_push_runner.dart';

import '../../helpers/fake_matrix.dart';

class _RecordingClient extends Client {
  @override
  bool isLogged() => true;

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

  test('back-to-back pushes share one client, let go without closing the '
      'database', () async {
    final built = <_RecordingClient>[];
    final runner = HeadlessPushRunner()
      ..clientBuilder = () async {
        final client = _RecordingClient();
        built.add(client);
        return client;
      };

    await handleFcmPush(
      runner,
      FcmPush(
        id: 'push',
        data: {'event_id': '\$one', 'room_id': '!room:example.org'},
        appInFront: false,
      ),
    );
    await handleFcmPush(
      runner,
      FcmPush(
        id: 'push',
        data: {'event_id': '\$two', 'room_id': '!room:example.org'},
        appInFront: false,
      ),
    );

    expect(built, hasLength(1));
    expect(built.single.resolveCalls, 2);
    expect(built.single.disposeCalls, 0);

    expect(await runner.settle(), isTrue);
    expect(built.single.disposeCalls, 1);
    expect(built.single.closedDatabase, isFalse);
  });

  test('opens no client at all for a payload with no event', () async {
    var builds = 0;
    final runner = HeadlessPushRunner()
      ..clientBuilder = () async {
        builds++;
        return _RecordingClient();
      };

    await handleFcmPush(
      runner,
      FcmPush(
        id: 'push',
        data: {'room_id': '!room:example.org'},
        appInFront: false,
      ),
    );

    expect(builds, 0);
  });

  test('a malformed payload is dropped without throwing', () async {
    final runner = HeadlessPushRunner()
      ..clientBuilder = () async => _RecordingClient();

    await handleFcmPush(
      runner,
      FcmPush(id: 'push', data: const {}, appInFront: false),
    );
  });
}
