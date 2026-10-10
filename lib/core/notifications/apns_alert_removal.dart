import 'package:flutter/services.dart';

import '../errors/caught_errors.dart';
import '../platform/platform_capabilities.dart';

const _channel = MethodChannel('zuno/apns');

class ApnsAlertRemoval {
  ApnsAlertRemoval({PlatformCapabilities? capabilities})
    : _injectedCapabilities = capabilities;

  final PlatformCapabilities? _injectedCapabilities;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  Future<int> removeForReadRooms(Iterable<String> roomIds) async {
    if (!_capabilities.apnsRegistration) return 0;
    final rooms = roomIds.toSet().toList()..sort();
    if (rooms.isEmpty) return 0;
    try {
      final removed = await _channel.invokeMethod<int>('removeDelivered', {
        'roomIds': rooms,
      });
      return removed ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException catch (e, s) {
      reportCaught('apns alert removal', e.code, s);
      return 0;
    }
  }
}

final apnsAlertRemoval = ApnsAlertRemoval();
