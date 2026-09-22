import 'package:flutter_test/flutter_test.dart';
import 'package:unifiedpush_platform_interface/data/public_key_set.dart';
import 'package:zuno/core/push/unified_push_pusher.dart';

void main() {
  final endpoint = Uri.parse('https://ntfy.sh/up1234567890abcdef');
  final gateway = Uri.parse('https://ntfy.sh/_matrix/push/v1/notify');

  test('builds a Pusher with the endpoint URL as pushkey', () {
    final pusher = buildUnifiedPushPusher(
      endpointUrl: endpoint,
      gatewayUrl: gateway,
      deviceDisplayName: 'Zuno on Android',
    );
    expect(pusher.appId, unifiedPushAppId);
    expect(pusher.pushkey, endpoint.toString());
    expect(pusher.appDisplayName, 'Zuno');
    expect(pusher.deviceDisplayName, 'Zuno on Android');
    expect(pusher.kind, 'http');
    expect(pusher.data.url, gateway);
    expect(pusher.data.format, 'event_id_only');
  });

  test('unifiedPushPusherIdFor matches buildUnifiedPushPusher\'s own id '
      'fields', () {
    final pusher = buildUnifiedPushPusher(
      endpointUrl: endpoint,
      gatewayUrl: gateway,
      deviceDisplayName: 'Zuno on Android',
    );
    final id = unifiedPushPusherIdFor(endpoint.toString());
    expect(id.appId, pusher.appId);
    expect(id.pushkey, pusher.pushkey);
  });

  test('builds a WebPush pusher keyed by the p256dh key, carrying the '
      'endpoint and auth secret for the gateway', () {
    final homeserverGateway = Uri.parse(
      'https://matrix.example.org/_matrix/push/v1/notify',
    );
    final pusher = buildUnifiedPushWebPusher(
      endpointUrl: endpoint,
      keys: PublicKeySet('P256KEY', 'AUTH'),
      gatewayUrl: homeserverGateway,
      deviceDisplayName: 'Zuno on Android',
    );
    expect(pusher.appId, unifiedPushAppId);
    expect(pusher.pushkey, 'P256KEY');
    expect(pusher.kind, 'http');
    expect(pusher.data.url, homeserverGateway);
    expect(pusher.data.format, 'event_id_only');
    expect(pusher.data.additionalProperties['endpoint'], endpoint.toString());
    expect(pusher.data.additionalProperties['auth'], 'AUTH');
  });

  test('unifiedPushPusherIdFor addresses a pusher by whatever key it used', () {
    expect(unifiedPushPusherIdFor('P256KEY').pushkey, 'P256KEY');
    expect(unifiedPushPusherIdFor('P256KEY').appId, unifiedPushAppId);
  });
}
