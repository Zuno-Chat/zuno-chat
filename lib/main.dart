import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/calls/notifications/call_notification_service.dart';
import 'core/calls/notifications/ringing_call_store.dart';
import 'core/errors/crash_reporting.dart';
import 'core/errors/global_error_handler.dart';
import 'core/matrix/matrix_client_provider.dart';
import 'core/push/fcm_startup.dart';
import 'core/push/unified_push_headless_entry.dart';
import 'core/security/screen_security_service.dart';
import 'core/settings/app_preferences_provider.dart';
import 'core/share/inbound_share.dart';
import 'core/shortcuts/home_screen_shortcut.dart';

const _unifiedPushBackgroundArg = '--unifiedpush-bg';

Future<void> main(List<String> args) async {
  runZonedGuarded(() => _runApp(args), reportZoneError);
}

Future<void> _runApp(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) debugPrint('zuno/push: main(args=$args)');
  if (args.contains(_unifiedPushBackgroundArg)) {
    await initHeadlessCrashReporting();
    await _runHeadlessPushHandler();
    return;
  }
  runApp(const ZunoBootSplash());
  final preferencesFuture = SharedPreferences.getInstance();
  await WidgetsBinding.instance.endOfFrame;
  final preferences = await preferencesFuture;
  await initCrashReporting(
    preferences,
    optedIn: readCrashReporting(preferences),
  );
  installGlobalErrorHandlers();
  initHomeScreenShortcutChannel();
  initInboundShareChannel();
  await initializeFcmDelivery();

  final imagePickerPlatform = ImagePickerPlatform.instance;
  if (imagePickerPlatform is ImagePickerAndroid) {
    imagePickerPlatform.useAndroidPhotoPicker = true;
  }

  final notificationsFuture = CallNotificationService.instance.initialize();
  final clientFuture = createMatrixClient();

  await notificationsFuture;
  final (:client, :uploadProgressHttpClient) = await clientFuture;
  client.shareKeysWith = shareKeysWithFor(
    readEncryptToVerifiedSessionsOnly(preferences),
  );
  unawaited(
    ScreenSecurityService.instance.setPreventScreenshots(
      readPreventScreenshots(preferences),
    ),
  );

  final pendingRing = readRingingCall(preferences);
  if (kDebugMode) {
    debugPrint('zuno/push: pending ring at startup = ${pendingRing?.callId}');
  }

  runApp(
    ProviderScope(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        uploadProgressHttpClientProvider.overrideWithValue(
          uploadProgressHttpClient,
        ),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: ZunoApp(pendingRing: pendingRing),
    ),
  );
}

Future<void> _runHeadlessPushHandler() => runUnifiedPushHeadless(
  clientBuilder: () async {
    final result = await createMatrixClient(backgroundSync: false);
    debugPrint('zuno/push: headless client ready');
    return result.client;
  },
);
