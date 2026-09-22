import 'package:flutter/services.dart';

import '../errors/best_effort.dart';

const _channel = MethodChannel('zuno/upload_service');

class UploadForegroundService {
  UploadForegroundService._();
  UploadForegroundService.forTest();

  static final instance = UploadForegroundService._();

  int _holders = 0;
  ({String label, int? percent})? _lastPosted;

  Future<void> acquire() async {
    if (_holders++ > 0) return;
    _lastPosted = null;
    await runBestEffort(
      () => _channel.invokeMethod('start'),
      label: 'upload service start',
    );
  }

  Future<void> release() async {
    if (_holders == 0) return;
    if (--_holders > 0) return;
    await runBestEffort(
      () => _channel.invokeMethod('stop'),
      label: 'upload service stop',
    );
  }

  Future<void> updateProgress({
    required String label,
    required double? fraction,
  }) async {
    if (_holders == 0) return;
    final percent = fraction == null ? null : (fraction * 100).round();
    final next = (label: label, percent: percent);
    if (_lastPosted == next) return;
    _lastPosted = next;
    await runBestEffort(
      () =>
          _channel.invokeMethod('update', {'label': label, 'percent': percent}),
      label: 'upload service progress',
    );
  }
}
