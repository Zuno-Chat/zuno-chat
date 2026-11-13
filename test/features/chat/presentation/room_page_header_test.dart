import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/security/security_emphasis.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/security/user_trust.dart';
import 'package:zuno/features/room_info/presentation/room_info_page.dart';

import '../../../helpers/fake_matrix.dart';
import 'room_page_harness.dart';

void main() {
  late RoomPageHarness harness;

  setUp(() => harness = RoomPageHarness());

  void setJoinRule(String rule) => harness.room.setState(
    buildTestEvent(
      harness.room,
      eventId: r'$join',
      senderId: '@creator:example.org',
      type: EventTypes.RoomJoinRules,
      stateKey: '',
      content: {'join_rule': rule},
    ),
  );

  testWidgets('says Public under the name of a public room', (tester) async {
    setJoinRule('public');
    await harness.pumpRoomPage(tester);

    expect(find.text('Public'), findsOneWidget);
    expect(find.text('Private'), findsNothing);
  });

  testWidgets('tapping the header of a private room opens room info', (
    tester,
  ) async {
    setJoinRule('invite');
    await harness.pumpRoomPage(tester);

    await tester.tap(find.text('Private'));
    await harness.settle(tester);

    expect(find.byType(RoomInfoPage), findsOneWidget);
  });

  group('the confirmed mark on the avatar', () {
    Finder mark() => find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(confirmedPersonIcon),
    );

    void trust(UserTrustState state) => harness = RoomPageHarness(
      overrides: [userTrustProvider.overrideWith((ref, _) => state)],
    );

    void makeDirectChat() =>
        harness.client.accountData['m.direct'] = BasicEvent(
          type: 'm.direct',
          content: {
            '@bob:example.org': [harness.room.id],
          },
        );

    testWidgets('shows on a chat with a confirmed person', (tester) async {
      trust(UserTrustState.confirmed);
      makeDirectChat();
      await harness.pumpRoomPage(tester);

      expect(mark(), findsOneWidget);
    });

    testWidgets('is absent for someone not confirmed', (tester) async {
      trust(UserTrustState.unconfirmed);
      makeDirectChat();
      await harness.pumpRoomPage(tester);

      expect(mark(), findsNothing);
    });

    testWidgets('never shows on a group, whoever is in it', (tester) async {
      trust(UserTrustState.confirmed);
      await harness.pumpRoomPage(tester);

      expect(mark(), findsNothing);
    });
  });

  group('the not-encrypted mark beside the name', () {
    Finder mark() => find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(NotEncryptedMark),
    );

    testWidgets('shows on a room that does not encrypt', (tester) async {
      await harness.pumpRoomPage(tester);

      expect(mark(), findsOneWidget);
    });

    testWidgets('is absent when messages here are sent encrypted', (
      tester,
    ) async {
      harness = RoomPageHarness(encrypting: true);
      encryptRoom(harness.room);
      await harness.pumpRoomPage(tester);

      expect(mark(), findsNothing);
    });

    testWidgets('shows on an encrypted room this device cannot encrypt for', (
      tester,
    ) async {
      encryptRoom(harness.room);
      await harness.pumpRoomPage(tester);

      expect(mark(), findsOneWidget);
    });
  });
}
