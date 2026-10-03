import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/apns_pusher.dart';
import 'package:zuno/core/push/push_diagnostics.dart';

import '../../helpers/platform_capabilities.dart';

const _channel = MethodChannel('zuno/push_diag');

Map<String, Object?> _snapshot({
  Map<String, Object?> settings = const {
    'authorization': 'authorized',
    'alert': 'enabled',
    'sound': 'disabled',
    'badge': 'enabled',
    'lockScreen': 'enabled',
    'notificationCenter': 'enabled',
    'carPlay': 'notSupported',
    'criticalAlert': 'notSupported',
    'announcement': 'disabled',
    'timeSensitive': 'enabled',
    'scheduledDelivery': 'disabled',
    'directMessages': 'notSupported',
    'alertStyle': 'banner',
    'showPreviews': 'whenAuthenticated',
    'providesAppSettings': false,
  },
  String environment = 'development',
  bool registered = true,
}) => {
  'settings': settings,
  'environment': environment,
  'registeredForRemoteNotifications': registered,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Object? reply;

  setUp(() {
    calls = [];
    reply = _snapshot();
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return reply;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  PushDiagnostics diagnostics({bool enabled = true}) => PushDiagnostics(
    capabilities: capabilitiesLike(iosCapabilities, pushDiagnostics: enabled),
  );

  test('reads every notification setting by name', () async {
    final settings = (await diagnostics().snapshot())!.settings;

    expect(calls.single.method, 'snapshot');
    expect(settings.authorization, PushAuthorization.authorized);
    expect(settings.alert, PushSetting.enabled);
    expect(settings.sound, PushSetting.disabled);
    expect(settings.badge, PushSetting.enabled);
    expect(settings.lockScreen, PushSetting.enabled);
    expect(settings.notificationCenter, PushSetting.enabled);
    expect(settings.carPlay, PushSetting.notSupported);
    expect(settings.criticalAlert, PushSetting.notSupported);
    expect(settings.announcement, PushSetting.disabled);
    expect(settings.timeSensitive, PushSetting.enabled);
    expect(settings.scheduledDelivery, PushSetting.disabled);
    expect(settings.directMessages, PushSetting.notSupported);
    expect(settings.alertStyle, PushAlertStyle.banner);
    expect(settings.previews, PushPreviews.whenAuthenticated);
    expect(settings.providesAppSettings, isFalse);
  });

  test('reads the push environment and whether Apple issued a token', () async {
    reply = _snapshot(environment: 'production', registered: false);

    final snapshot = (await diagnostics().snapshot())!;

    expect(snapshot.environment, ApnsEnvironment.production);
    expect(snapshot.registeredForRemoteNotifications, isFalse);
  });

  test('names it does not know read as unknown, never as a wrong '
      'answer', () async {
    reply = _snapshot(
      settings: const {'authorization': 'later', 'alert': 'sometimes'},
      environment: 'staging',
    );

    final snapshot = (await diagnostics().snapshot())!;

    expect(snapshot.settings.authorization, PushAuthorization.unknown);
    expect(snapshot.settings.alert, PushSetting.unknown);
    expect(snapshot.settings.sound, PushSetting.unknown);
    expect(snapshot.settings.alertStyle, PushAlertStyle.unknown);
    expect(snapshot.settings.previews, PushPreviews.unknown);
    expect(snapshot.environment, isNull);
  });

  test('a reply without settings is no snapshot', () async {
    reply = {'environment': 'production'};

    expect(await diagnostics().snapshot(), isNull);
  });

  test('asks nothing while diagnostics are off', () async {
    expect(await diagnostics(enabled: false).snapshot(), isNull);
    expect(calls, isEmpty);
  });

  test('without the native handler there is no snapshot and nothing '
      'throws', () async {
    messenger.setMockMethodCallHandler(_channel, null);

    expect(await diagnostics().snapshot(), isNull);
  });

  test('a native failure is no snapshot', () async {
    messenger.setMockMethodCallHandler(
      _channel,
      (call) async => throw PlatformException(code: 'unavailable'),
    );

    expect(await diagnostics().snapshot(), isNull);
  });
}
