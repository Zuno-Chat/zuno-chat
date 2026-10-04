import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../matrix/matrix_client_provider.dart';
import '../notifications/apns_delivery_provider.dart';
import '../notifications/fcm_delivery_provider.dart';
import '../notifications/notification_delivery_mode.dart';
import '../notifications/notification_delivery_provider.dart';
import '../platform/platform_capabilities.dart';
import 'fcm_bridge.dart';
import 'push_delivery_log.dart';
import 'push_diagnostics.dart' show PushDiagnostics;
import 'push_diagnostics_data.dart';
import 'push_diagnostics_report.dart';
import 'pusher_reconciliation.dart';
import 'recent_pushes.dart';
import 'voip/voip_channel.dart';
import 'zuno_push_api.dart' hide PusherHealth;

enum PushTestOutcome { sent, rateLimited, notAvailable, failed }

abstract interface class PushDiagnosticsSource {
  Future<PushDiagnosticsInputs> load(
    PlatformCapabilities capabilities,
    NotificationDeliveryMode mode,
  );

  Future<PushTestOutcome> sendTest();

  Future<List<RecentPush>> recentPushes(
    PlatformCapabilities capabilities,
    NotificationDeliveryMode mode,
  );
}

final pushDiagnosticsSourceProvider = Provider<PushDiagnosticsSource>(
  (ref) => LivePushDiagnosticsSource(ref.watch(matrixClientProvider)),
);

class LivePushDiagnosticsSource implements PushDiagnosticsSource {
  LivePushDiagnosticsSource(
    this.client, {
    http.Client? httpClient,
    DateTime Function()? now,
  }) : _injectedHttpClient = httpClient,
       _now = now ?? DateTime.now;

  final Client client;
  final http.Client? _injectedHttpClient;
  final DateTime Function() _now;

  @override
  Future<PushDiagnosticsInputs> load(
    PlatformCapabilities capabilities,
    NotificationDeliveryMode mode,
  ) async {
    final snapshot = await PushDiagnostics(capabilities: capabilities)
        .rawSnapshot();
    final voip = await _voipStatus(capabilities);
    final (health, reach) = await _health();
    final pushers = await fetchPushers(client);
    final info = await PackageInfo.fromPlatform();
    final offersFcm = capabilities.deliveryModes.contains(
      NotificationDeliveryMode.fcm,
    );
    return PushDiagnosticsInputs(
      capabilities: capabilities,
      now: _now(),
      appVersion: '${info.version} (build ${info.buildNumber})',
      snapshot: PushDiagnosticsSnapshot.fromChannel(snapshot),
      voip: voip,
      health: health,
      reach: reach,
      pushers: pushers,
      currentPushkey: currentPushkeyFor(mode),
      expectedGateway: gatewayUrlFor(mode, client),
      deliveryMode: mode,
      fcmStatus: mode == NotificationDeliveryMode.fcm
          ? fcmDeliveryProvider.status.value
          : null,
      unifiedPushStatus: mode == NotificationDeliveryMode.unifiedPush
          ? unifiedPushDeliveryProvider.status.value
          : null,
      playServices: offersFcm
          ? await FcmBridge(capabilities: capabilities).availability()
          : null,
      deliveries: mode == NotificationDeliveryMode.fcm
          ? await readPushDeliveryLog(await SharedPreferences.getInstance())
          : null,
      droppedRegistrations: mode == NotificationDeliveryMode.apns
          ? apnsDeliveryProvider.dropped.value
          : null,
    );
  }

  @override
  Future<List<RecentPush>> recentPushes(
    PlatformCapabilities capabilities,
    NotificationDeliveryMode mode,
  ) async {
    switch (mode) {
      case NotificationDeliveryMode.fcm:
        return recentPushesFromDeliveries(
          await readPushDeliveryLog(await SharedPreferences.getInstance()),
        );
      case NotificationDeliveryMode.apns:
        final snapshot = PushDiagnosticsSnapshot.fromChannel(
          await PushDiagnostics(capabilities: capabilities).rawSnapshot(),
        );
        return recentPushesFromLogs(
          extension: snapshot.extensionLog,
          app: snapshot.appLog,
          ledger: snapshot.ledger ?? const [],
        );
      case NotificationDeliveryMode.unifiedPush:
      case NotificationDeliveryMode.backgroundService:
        return const [];
    }
  }

  @override
  Future<PushTestOutcome> sendTest() async {
    final api = _openApi();
    if (api == null) return PushTestOutcome.failed;
    try {
      return switch (await api.sendTestAlert()) {
        ZunoPushOk() => PushTestOutcome.sent,
        ZunoPushFailure(kind: ZunoPushFailureKind.rateLimited) =>
          PushTestOutcome.rateLimited,
        ZunoPushFailure(kind: ZunoPushFailureKind.disabled) =>
          PushTestOutcome.notAvailable,
        ZunoPushFailure(
          kind: ZunoPushFailureKind.route,
          status: final int status,
        )
            when status < 500 =>
          PushTestOutcome.notAvailable,
        ZunoPushFailure() => PushTestOutcome.failed,
      };
    } finally {
      api.close();
    }
  }

  Future<VoipDeviceStatus?> _voipStatus(
    PlatformCapabilities capabilities,
  ) async {
    final status = await VoipChannel(capabilities: capabilities).status();
    if (status == null) return null;
    return VoipDeviceStatus(
      hasToken: status.token?.isNotEmpty ?? false,
      callKit: status.callKit,
      environment: status.environment,
      kid: status.kid,
    );
  }

  Future<(ServerHealth?, ServerReach)> _health() async {
    final api = _openApi();
    if (api == null) return (null, ServerReach.unreachable);
    final askedAt = _now();
    try {
      switch (await api.health()) {
        case ZunoPushOk(:final value, :final serverTs):
          DateTime? at(int? milliseconds) => milliseconds == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(milliseconds);
          return (
            ServerHealth(
              pushers: [
                for (final pusher in value.pushers)
                  PusherHealth(
                    appId: pusher.appId,
                    lastSuccess: at(pusher.lastSuccessTs),
                    failingSince: at(pusher.failingSinceTs),
                  ),
              ],
              voipRegistered: value.voip.registered,
              voipKid: value.voip.kid,
              voipLastResult: value.voip.lastResult?.name,
              voipLastAt: at(value.voip.lastTs),
              credentialExpires: at(value.nse.credentialExpiresTs),
              lastFetch: at(value.nse.lastFetchTs),
              serverOffset: DateTime.fromMillisecondsSinceEpoch(serverTs)
                  .difference(askedAt),
            ),
            ServerReach.reachable,
          );
        case ZunoPushFailure(:final kind, :final errcode, :final status):
          return (
            null,
            switch ((kind, errcode, status)) {
              (ZunoPushFailureKind.disabled, _, _) => ServerReach.turnedOff,
              (ZunoPushFailureKind.route, _, final int code) when code < 500 =>
                ServerReach.notInstalled,
              (_, 'IM.ZUNO.STARTING', _) => ServerReach.starting,
              _ => ServerReach.unreachable,
            },
          );
      }
    } finally {
      api.close();
    }
  }

  ZunoPushApi? _openApi() {
    try {
      return ZunoPushApi.forClient(client, httpClient: _injectedHttpClient);
    } on StateError {
      return null;
    }
  }
}
