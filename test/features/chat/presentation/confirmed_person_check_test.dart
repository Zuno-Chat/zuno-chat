import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/security/user_trust.dart';
import 'package:zuno/features/chat/presentation/confirmed_person_check.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
    client.rooms.add(room);
  });

  void makeDirectChat() => client.accountData['m.direct'] = BasicEvent(
    type: 'm.direct',
    content: {
      '@bob:example.org': [room.id],
    },
  );

  Future<void> pump(WidgetTester tester, UserTrustState trust) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [userTrustProvider.overrideWith((ref, _) => trust)],
          child: MaterialApp(
            home: Scaffold(body: ConfirmedPersonCheck(room: room)),
          ),
        ),
      );

  Finder check() => find.bySemanticsLabel('Confirmed');

  for (final trust in [
    UserTrustState.confirmed,
    UserTrustState.confirmedWithPendingDevice,
  ]) {
    testWidgets('a ${trust.name} person gets the check', (tester) async {
      makeDirectChat();
      await pump(tester, trust);

      expect(check(), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });
  }

  for (final trust in [
    UserTrustState.noIdentity,
    UserTrustState.unconfirmed,
    UserTrustState.identityChanged,
  ]) {
    testWidgets('a ${trust.name} person gets none', (tester) async {
      makeDirectChat();
      await pump(tester, trust);

      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    });
  }

  testWidgets('a room never gets one, whoever is in it', (tester) async {
    await pump(tester, UserTrustState.confirmed);

    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
  });
}
