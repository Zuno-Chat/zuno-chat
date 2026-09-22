import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/push/fcm_background_handler.dart';
import 'package:zuno/core/push/incoming_push_handler.dart';

import '../../helpers/fake_matrix.dart';

class _RecordingClient extends Client {
  _RecordingClient({this.onDispose})
    : super('test', database: FakeDatabaseApi());

  final void Function()? onDispose;

  @override
  Future<Event?> getEventByPushNotification(
    PushNotification notification, {
    bool storeInDatabase = true,
    Duration timeoutForServerRequests = const Duration(seconds: 8),
    bool returnNullIfSeen = true,
  }) async => null;

  @override
  Future<void> dispose({bool closeDatabase = true}) async => onDispose?.call();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetFcmBackgroundRunnerForTesting();
    resetForegroundFcmListenerForTesting();
  });

  tearDown(() {
    resetForegroundFcmListenerForTesting();
    foregroundFcmMessages = () => FirebaseMessaging.onMessage;
  });

  group('the ring hold', () {
    test(
      'does not delay the handler, so the hang-up push can get through',
      () async {
        final holdStarted = Completer<void>();
        final releaseHold = Completer<void>();
        final runner = buildFcmBackgroundRunner(
          clientBuilder: () async => _RecordingClient(),
          hold: (_) {
            holdStarted.complete();
            return releaseHold.future;
          },
        );

        await runner.onPushHandled!(IncomingPushOutcome.callRinging).timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('the ring hold blocked the FCM work item'),
        );

        expect(holdStarted.isCompleted, isTrue);
        expect(releaseHold.isCompleted, isFalse);
        releaseHold.complete();
      },
    );

    test('is not started for a push that is not a ring', () async {
      var holds = 0;
      final runner = buildFcmBackgroundRunner(
        clientBuilder: () async => _RecordingClient(),
        hold: (_) async => holds++,
      );

      for (final outcome in IncomingPushOutcome.values) {
        if (outcome == IncomingPushOutcome.callRinging) continue;
        await runner.onPushHandled!(outcome);
      }
      await pumpEventQueue();

      expect(holds, 0);
    });

    test('a throwing hold is swallowed rather than left unhandled', () async {
      final runner = buildFcmBackgroundRunner(
        clientBuilder: () async => _RecordingClient(),
        hold: (_) async => throw StateError('port already claimed'),
      );

      await runner.onPushHandled!(IncomingPushOutcome.callRinging);
      await pumpEventQueue();
    });
  });

  group('the background runner', () {
    test('is one per isolate, not one per message', () {
      expect(identical(fcmBackgroundRunner(), fcmBackgroundRunner()), isTrue);
    });

    test('serializes a burst so two clients never overlap', () async {
      var open = 0;
      var maxOpen = 0;
      final runner = buildFcmBackgroundRunner(
        clientBuilder: () async {
          open++;
          maxOpen = open > maxOpen ? open : maxOpen;
          return _RecordingClient(onDispose: () => open--);
        },
        hold: (_) async {},
      );

      await Future.wait([
        for (var i = 0; i < 5; i++)
          handleFcmMessage(runner, {
            'event_id': '\$burst$i',
            'room_id': '!room:example.org',
          }),
      ]);

      expect(maxOpen, 1);
    });
  });

  group('the foreground listener', () {
    test('subscribes once however many times startup re-enters', () {
      var subscriptions = 0;
      foregroundFcmMessages = () {
        subscriptions++;
        return const Stream<RemoteMessage>.empty();
      };

      listenForForegroundFcmMessages();
      listenForForegroundFcmMessages();
      listenForForegroundFcmMessages();

      expect(subscriptions, 1);
    });
  });
}
