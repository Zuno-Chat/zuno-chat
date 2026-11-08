import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' show Client;

import '../matrix/client/matrix_client_provider.dart';
import 'cloudflare/cloudflare_connection.dart';
import 'livekit/livekit_connection.dart';
import 'media/call_connection.dart';
import 'module/call_provider_discovery.dart';
import 'module/calls_offer_provider.dart';

class CallConnections implements CallConnectionOpener {
  CallConnections({
    required this._client,
    required this._discovery,
    this._httpClient,
  });

  final Client _client;
  final CallProviderDiscovery _discovery;
  final http.Client? _httpClient;

  @override
  Future<CallConnection> open(
    CallSpec spec,
    CallConnectionHost host, {
    bool rediscover = false,
  }) async {
    final offer = rediscover
        ? await _discovery.refetch()
        : await _discovery.current();
    return switch (offer) {
      CallsOffer.none => throw const CallsNotOffered(),
      CallsOffer.cloudflare => CloudflareConnection.forClient(
        _client,
        spec: spec,
        host: host,
        httpClient: _httpClient,
      ),
      CallsOffer.livekit => LiveKitConnection(
        client: _client,
        spec: spec,
        host: host,
        httpClient: _httpClient,
      ),
    };
  }
}

final callConnectionsProvider = Provider<CallConnectionOpener>(
  (ref) => CallConnections(
    client: ref.watch(matrixClientProvider),
    discovery: ref.watch(callProviderDiscoveryProvider),
  ),
);
