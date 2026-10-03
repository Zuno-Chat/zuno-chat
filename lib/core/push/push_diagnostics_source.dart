import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../matrix/matrix_client_provider.dart';
import '../notifications/apns_delivery_provider.dart';
import '../platform/platform_capabilities.dart';
import 'fcm_gateway.dart';
import 'push_diagnostics.dart' show PushDiagnostics;
import 'push_diagnostics_data.dart';
import 'push_diagnostics_report.dart';
import 'pusher_reconciliation.dart';
import 'voip/voip_channel.dart';
import 'zuno_push_api.dart' hide PusherHealth;

enum PushTestOutcome { sent, rateLimited, failed }

abstract interface class PushDiagnosticsSource {
  Future<PushDiagnosticsInputs> load(PlatformCapabilities capabilities);

  Future<PushTestOutcome> sendTest();
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
  Future<PushDiagnosticsInputs> load(PlatformCapabilities capabilities) async {
    final snapshot = await PushDiagnostics(capabilities: capabilities)
        .rawSnapshot();
    final voip = await _voipStatus(capabilities);
    final (health, reach) = await _health();
    final pushers = await fetchPushers(client);
    final info = await PackageInfo.fromPlatform();
    return PushDiagnosticsInputs(
      capabilities: capabilities,
      now: _now(),
      appVersion: '${info.version} (build ${info.buildNumber})',
      snapshot: PushDiagnosticsSnapshot.fromChannel(snapshot),
      voip: voip,
      health: health,
      reach: reach,
      pushers: pushers,
      currentPushkey: apnsDeliveryProvider.pushkey,
      expectedGateway: fcmGatewayUri(client.homeserver),
    );
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
        case ZunoPushFailure(:final kind, :final errcode):
          return (
            null,
            switch ((kind, errcode)) {
              (ZunoPushFailureKind.disabled, _) => ServerReach.turnedOff,
              (_, 'IM.ZUNO.STARTING') => ServerReach.starting,
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
