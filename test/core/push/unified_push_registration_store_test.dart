import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/push/unified_push_registration_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final endpoint = Uri.parse('https://ntfy.sh/upABC');
  final gateway = Uri.parse('https://ntfy.sh/_matrix/push/v1/notify');

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  test('round-trips an endpoint and gateway', () async {
    final prefs = await prefsWith({});

    await saveUnifiedPushRegistration(
      prefs,
      endpointUrl: endpoint,
      gatewayUrl: gateway,
    );

    final stored = readUnifiedPushRegistration(prefs);
    expect(stored?.endpointUrl, endpoint);
    expect(stored?.gatewayUrl, gateway);
  });

  test('reads back an endpoint saved without a resolved gateway', () async {
    final prefs = await prefsWith({});

    await saveUnifiedPushRegistration(prefs, endpointUrl: endpoint);

    final stored = readUnifiedPushRegistration(prefs);
    expect(stored?.endpointUrl, endpoint);
    expect(stored?.gatewayUrl, isNull);
  });

  test('nothing stored means not registered', () async {
    expect(readUnifiedPushRegistration(await prefsWith({})), isNull);
  });

  test('a corrupt endpoint counts as not registered', () async {
    final prefs = await prefsWith({'push.unified_push.endpoint': 'nonsense'});

    expect(readUnifiedPushRegistration(prefs), isNull);
  });

  test('clear() forgets the registration', () async {
    final prefs = await prefsWith({});
    await saveUnifiedPushRegistration(
      prefs,
      endpointUrl: endpoint,
      gatewayUrl: gateway,
    );

    await clearUnifiedPushRegistration(prefs);

    expect(readUnifiedPushRegistration(prefs), isNull);
  });

  test('remembers a pushkey that differs from the endpoint', () async {
    final prefs = await prefsWith({});

    await saveUnifiedPushRegistration(
      prefs,
      endpointUrl: endpoint,
      gatewayUrl: gateway,
      pushkey: 'P256KEY',
      auth: 'AUTH',
    );

    final stored = readUnifiedPushRegistration(prefs);
    expect(stored?.pushkey, 'P256KEY');
    expect(stored?.auth, 'AUTH');
  });

  test(
    'the pushkey defaults to the endpoint for an older registration',
    () async {
      final prefs = await prefsWith({});

      await saveUnifiedPushRegistration(prefs, endpointUrl: endpoint);

      expect(readUnifiedPushRegistration(prefs)?.pushkey, endpoint.toString());
    },
  );
}
