import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../async/serial_lock.dart';
import '../../l10n/l10n.dart';
import '../../notifications/settings/notification_preview.dart';
import '../../platform/platform_capabilities.dart';

const _callsChannel = MethodChannel('zuno/calls');

abstract interface class OngoingCallPresenter {
  Future<void> start({required String title, required bool withCamera});

  Future<void> stop();
}

OngoingCallPresenter ongoingCallPresenterFor(
  PlatformCapabilities capabilities,
) => capabilities.callForegroundService
    ? const AndroidOngoingCallPresenter()
    : const NoopOngoingCallPresenter();

final ongoingCallPresenterProvider = Provider<OngoingCallPresenter>(
  (ref) => ongoingCallPresenterFor(ref.watch(platformCapabilitiesProvider)),
);

class AndroidOngoingCallPresenter implements OngoingCallPresenter {
  const AndroidOngoingCallPresenter();

  static final _inOrder = SerialLock();

  @override
  Future<void> start({required String title, required bool withCamera}) {
    final preview = currentNotificationPreview();
    return _inOrder.run(() async {
      final l10n = deviceLocalizations();
      await _invoke('startCallForegroundService', {
        'title': (await preview).callName(title, l10n),
        'text': l10n.callsOngoingTapToReturn,
        'withCamera': withCamera,
      });
    });
  }

  @override
  Future<void> stop() =>
      _inOrder.run(() => _invoke<void>('stopCallForegroundService'));

  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _callsChannel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    }
  }
}

class NoopOngoingCallPresenter implements OngoingCallPresenter {
  const NoopOngoingCallPresenter();

  @override
  Future<void> start({required String title, required bool withCamera}) async {}

  @override
  Future<void> stop() async {}
}
