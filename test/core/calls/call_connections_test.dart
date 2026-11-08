import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/call_connections.dart';
import 'package:zuno/core/calls/livekit/livekit_connection.dart';
import 'package:zuno/core/calls/media/call_connection.dart';
import 'package:zuno/core/calls/module/call_provider_discovery.dart';

import '../../helpers/fake_call_provider_discovery.dart';
import '../../helpers/fake_matrix.dart';

class _Host extends Fake implements CallConnectionHost {}

const _spec = (roomId: '!room:example.org', callId: 'call1');

void main() {
  CallConnections build(FakeCallProviderDiscovery discovery) => CallConnections(
    client: buildTestClient(userId: '@me:example.org'),
    discovery: discovery,
  );

  test('open reads the cached answer and rediscover asks again', () async {
    final discovery = FakeCallProviderDiscovery(CallsOffer.none);
    final connections = build(discovery);

    await expectLater(
      connections.open(_spec, _Host()),
      throwsA(isA<CallsNotOffered>()),
    );
    expect((discovery.currentCalls, discovery.refetchCalls), (1, 0));

    await expectLater(
      connections.open(_spec, _Host(), rediscover: true),
      throwsA(isA<CallsNotOffered>()),
    );
    expect((discovery.currentCalls, discovery.refetchCalls), (1, 1));
  });

  test('a LiveKit answer opens a LiveKit connection', () async {
    final connections = build(FakeCallProviderDiscovery(CallsOffer.livekit));

    final connection = await connections.open(_spec, _Host());

    expect(connection, isA<LiveKitConnection>());
    await connection.close();
  });
}
