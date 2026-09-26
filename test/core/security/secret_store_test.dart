import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/security/secret_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  });

  test(
    'on iOS secrets stay readable after the first unlock, so a push '
    'handled while the phone is locked can still open the database',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const store = SecureSecretStore();

      await store.write('database_key', 'secret');
      await store.read('database_key');
      await store.delete('database_key');

      expect(
        calls.map(
          (c) => (
            c.method,
            ((c.arguments as Map)['options'] as Map)['accessibility'],
          ),
        ),
        [
          ('write', 'first_unlock_this_device'),
          ('read', 'first_unlock_this_device'),
          ('delete', 'first_unlock_this_device'),
        ],
      );
    },
  );
}
