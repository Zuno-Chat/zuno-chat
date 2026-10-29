import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import 'calls/notifications/headless_call_decline_provider.dart';
import 'calls/ring_coordinator.dart';
import 'location/live_location_viewing.dart';
import 'matrix/matrix_client_provider.dart';
import 'matrix/sync_coordinator_provider.dart';
import 'notifications/actions/headless_message_action_provider.dart';
import 'notifications/join_request_notification_provider.dart';
import 'notifications/messages/conversation_tones.dart';
import 'notifications/messages/message_notification_provider.dart';
import 'notifications/room_invite_notification_provider.dart';
import 'notifications/server_push_rules.dart';
import 'push/apns/apns_delivery_provider.dart';
import 'push/delivery/delivery_auto_fallback.dart';
import 'push/nse/nse_services.dart';
import 'security/alerts/security_alerts_provider.dart';
import 'shortcuts/conversation_shortcuts.dart';

final appServicesProvider = Provider<void>((ref) {
  for (final service in _alwaysOn) {
    ref.listen(service, (_, _) {});
  }
  if (ref.watch(isLoggedInProvider).value != true ||
      ref.watch(signInInFlightProvider)) {
    return;
  }
  for (final service in _signedIn) {
    ref.listen(service, (_, _) {});
  }
});

final List<ProviderListenable<Object?>> _alwaysOn = [
  pushRingServicesProvider,
  nseServicesProvider,
  liveLocationViewingProvider,
  syncReasonsProvider,
  conversationShortcutsProvider,
];

final List<ProviderListenable<Object?>> _signedIn = [
  headlessCallDeclineProvider,
  messageNotificationProvider,
  roomInviteNotificationProvider,
  joinRequestNotificationProvider,
  headlessMessageActionProvider,
  pushRuleMaintenanceProvider,
  deliveryAutoFallbackProvider,
  securityAlertsProvider,
  apnsMessageToneProvider,
  conversationTonePlayerProvider,
];
