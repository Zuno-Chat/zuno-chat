import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  Future<void> start({required String title, required bool withCamera}) {
    return _invoke('startCallForegroundService', {
      'title': title,
      'text': 'Tap to return to the call',
      'withCamera': withCamera,
    });
  }

  @override
  Future<void> stop() => _invoke('stopCallForegroundService');

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
