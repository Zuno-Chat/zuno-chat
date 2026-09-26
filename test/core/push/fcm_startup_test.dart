import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_messaging_platform_interface/firebase_messaging_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/fcm_background_handler.dart';
import 'package:zuno/core/push/fcm_startup.dart';

class _FakeFirebase extends FirebasePlatform {
  Object? failure;
  int starts = 0;

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    starts++;
    if (failure case final error?) throw error;
    return FirebaseAppPlatform(
      defaultFirebaseAppName,
      const FirebaseOptions(
        apiKey: 'key',
        appId: 'app',
        messagingSenderId: 'sender',
        projectId: 'project',
      ),
    );
  }
}

class _FakeMessaging extends FirebaseMessagingPlatform {
  final backgroundHandlers = <BackgroundMessageHandler>[];

  @override
  Future<void> registerBackgroundMessageHandler(
    BackgroundMessageHandler handler,
  ) async => backgroundHandlers.add(handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isDuplicateFirebaseAppError', () {
    test('true for a [core/duplicate-app] FirebaseException', () {
      expect(
        isDuplicateFirebaseAppError(
          FirebaseException(plugin: 'core', code: 'duplicate-app'),
        ),
        isTrue,
      );
    });

    test('false for a different FirebaseException code', () {
      expect(
        isDuplicateFirebaseAppError(
          FirebaseException(plugin: 'core', code: 'no-app'),
        ),
        isFalse,
      );
    });

    test('false for a non-FirebaseException error', () {
      expect(isDuplicateFirebaseAppError(StateError('boom')), isFalse);
    });
  });

  group('initializeFcmDelivery', () {
    final firebase = _FakeFirebase();
    final messaging = _FakeMessaging();

    setUpAll(() {
      FirebasePlatform.instance = firebase;
      FirebaseMessagingPlatform.instance = messaging;
    });

    setUp(() {
      firebase
        ..failure = null
        ..starts = 0;
      messaging.backgroundHandlers.clear();
    });

    test('starts Firebase, then takes pushes in the background and the '
        'foreground', () async {
      await initializeFcmDelivery();

      expect(firebase.starts, 1);
      expect(messaging.backgroundHandlers, [fcmBackgroundHandler]);
      expect(FirebaseMessagingPlatform.onMessage.hasListener, isTrue);
    });

    test(
      'carries on when Firebase is already running after a hot restart',
      () async {
        firebase.failure = FirebaseException(
          plugin: 'core',
          code: 'duplicate-app',
        );

        await initializeFcmDelivery();

        expect(messaging.backgroundHandlers, [fcmBackgroundHandler]);
      },
    );

    for (final (label, failure) in [
      ('Firebase', FirebaseException(plugin: 'core', code: 'no-app')),
      ('the platform', StateError('no Google Play services')),
    ]) {
      test('a failure inside $label never propagates, and no push handler '
          'is registered', () async {
        firebase.failure = failure;

        await expectLater(initializeFcmDelivery(), completes);
        expect(messaging.backgroundHandlers, isEmpty);
      });
    }
  });
}
