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
import 'core/matrix/client_startup.dart';
import 'core/matrix/matrix_client_provider.dart';
import 'core/network/user_agent.dart';
import 'core/notifications/native_notification_action_runner.dart';
import 'core/platform/platform_capabilities.dart';
import 'core/push/fcm_headless_entry.dart';
import 'core/push/fcm_startup.dart';
import 'core/push/unified_push_headless_entry.dart';
import 'core/security/screen_security_service.dart';
import 'core/settings/app_preferences_provider.dart';
import 'core/share/inbound_share.dart';
import 'core/shortcuts/home_screen_shortcut.dart';
import 'features/startup/presentation/startup_failure_page.dart';

const _unifiedPushBackgroundArg = '--unifiedpush-bg';
const _fcmBackgroundArg = '--fcm-bg';

Future<void> main(List<String> args) async {
  runZonedGuarded(() => _runApp(args), reportZoneError);
}

Future<void> _runApp(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await installUserAgent();
  if (kDebugMode) debugPrint('zuno/push: main(args=$args)');
  if (args.contains(_fcmBackgroundArg)) {
    await runFcmHeadless();
    return;
  }
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
  final clientFuture = startClientOrAsk(
    first: createMatrixClient(),
    askUser: _askAfterFailedStart,
    retry: createMatrixClient,
    startOver: startOverWithFreshStore,
    report: reportZoneError,
  );

  await notificationsFuture;
  final (:client, :uploadProgressHttpClient) = await clientFuture;
  attachFcmAppClient(client);
  if (ambientCapabilities.nativeNotificationActions) {
    nativeNotificationActionRunner.attach(client);
  }
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

Future<StartupChoice> _askAfterFailedStart(Object _) async {
  final choice = Completer<StartupChoice>();
  runApp(
    StartupFailureApp(
      onChoice: (chosen) {
        if (!choice.isCompleted) choice.complete(chosen);
      },
    ),
  );
  final chosen = await choice.future;
  runApp(const ZunoBootSplash());
  return chosen;
}

Future<void> _runHeadlessPushHandler() => runUnifiedPushHeadless(
  clientBuilder: () async {
    final result = await createMatrixClient(backgroundSync: false);
    debugPrint('zuno/push: headless client ready');
    return result.client;
  },
);
