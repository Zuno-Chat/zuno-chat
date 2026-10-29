import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/security/alerts/room_security_alerts_provider.dart';
import 'package:zuno/core/security/alerts/security_alert.dart';
import 'package:zuno/core/security/alerts/security_alerts_provider.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/security/user_trust.dart';

import '../../../helpers/fake_matrix.dart';

const _me = '@me:example.org';
const _bob = '@bob:example.org';
const _carol = '@carol:example.org';

class _Alerts extends SecurityAlertsNotifier {
  @override
  List<RecordedSecurityAlert> build() => const [];
}

void main() {
  late Client client;
  late Room room;
  late Room other;
  late Map<String, UserTrustState> trust;
  late List<String> trustReads;

  setUp(() {
    client = buildTestClient(userId: _me);
    room = buildTestRoom(client);
    other = buildTestRoom(client, id: '!other:example.org');
    client.rooms.addAll([room, other]);
    room.setState(User(_me, membership: 'join', room: room));
    room.setState(User(_bob, membership: 'join', room: room));
    trust = {_carol: UserTrustState.identityChanged};
    trustReads = [];
  });

  Future<List<List<SecurityAlert>>> watch(WidgetTester tester) async {
    final seen = <List<SecurityAlert>>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixClientProvider.overrideWithValue(client),
          securityAlertsProvider.overrideWith(_Alerts.new),
          userTrustProvider.overrideWith((ref, userId) {
            trustReads.add(userId);
            return trust[userId] ?? UserTrustState.confirmed;
          }),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            seen.add(ref.watch(roomSecurityAlertsProvider(room)));
            return const SizedBox();
          },
        ),
      ),
    );
    return seen;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  testWidgets('someone joining whose identity changed raises the alert', (
    tester,
  ) async {
    final seen = await watch(tester);
    expect(seen.last, isEmpty);

    room.setState(User(_carol, membership: 'join', room: room));
    await settle(tester);

    expect(seen.last, const [IdentityChangedAlert(_carol)]);
  });

  testWidgets('a change elsewhere does not scan the members again', (
    tester,
  ) async {
    final seen = await watch(tester);
    await settle(tester);
    final builds = seen.length;
    trustReads.clear();

    other.setState(User(_carol, membership: 'join', room: other));
    room.setState(
      buildTestEvent(
        room,
        eventId: r'$topic',
        senderId: _bob,
        type: EventTypes.RoomTopic,
        stateKey: '',
        content: {'topic': 'Plans'},
      ),
    );
    await settle(tester);

    expect(seen, hasLength(builds));
    expect(trustReads, isEmpty);
  });
}
