import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/fcm_startup.dart';

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
    test(
      'a genuine Firebase.initializeApp failure never propagates',
      () async {
        await expectLater(initializeFcmDelivery(), completes);
      },
    );
  });
}
