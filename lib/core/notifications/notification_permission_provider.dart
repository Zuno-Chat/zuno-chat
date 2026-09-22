import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

final notificationsAllowedProvider =
    NotifierProvider<NotificationsAllowedNotifier, bool?>(
      NotificationsAllowedNotifier.new,
    );

class NotificationsAllowedNotifier extends Notifier<bool?> {
  @override
  bool? build() {
    unawaited(refresh());
    return null;
  }

  Future<bool?> refresh() async {
    try {
      final allowed = (await Permission.notification.status).isGranted;
      if (state != allowed) state = allowed;
      return allowed;
    } catch (_) {
      return state;
    }
  }
}
