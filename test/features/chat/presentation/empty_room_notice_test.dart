import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/security/user_trust.dart';
import 'package:zuno/features/chat/presentation/empty_room_notice.dart';
import 'package:zuno/features/verification/presentation/why_confirm_sheet.dart';

import '../../../helpers/fake_matrix.dart';

const _sam = '@sam:example.org';
const _encrypted = 'Messages here are end-to-end encrypted.';
const _unconfirmed =
    '$_encrypted Once you confirm it is really @sam, only the two of you can '
    'read them.';

void main() {
  late Room room;

  setUp(() {
    final client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
    client.rooms.add(room);
  });

  void encrypt() => room.setState(
    StrippedStateEvent(
      type: EventTypes.Encryption,
      senderId: '@me:example.org',
      stateKey: '',
      content: {'algorithm': 'm.megolm.v1.aes-sha2'},
    ),
  );

  void makeDirectChat() => room.client.accountData['m.direct'] = BasicEvent(
    type: 'm.direct',
    content: {
      _sam: [room.id],
    },
  );

  Future<void> pump(WidgetTester tester, UserTrustState trust) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [userTrustProvider.overrideWith((ref, _) => trust)],
          child: MaterialApp(
            home: Scaffold(body: EmptyRoomNotice(room: room)),
          ),
        ),
      );

  Finder why() => find.text('Why confirm');

  testWidgets('an unencrypted room says nothing', (tester) async {
    makeDirectChat();
    await pump(tester, UserTrustState.unconfirmed);

    expect(find.byType(Text), findsNothing);
  });

  testWidgets('a room with several people keeps its line and no link', (
    tester,
  ) async {
    encrypt();
    await pump(tester, UserTrustState.unconfirmed);

    expect(
      find.text('$_encrypted Only the people in this chat can read them.'),
      findsOneWidget,
    );
    expect(why(), findsNothing);
  });

  for (final trust in [
    UserTrustState.unconfirmed,
    UserTrustState.identityChanged,
  ]) {
    testWidgets('a chat with someone ${trust.name} promises nothing it cannot '
        'keep and offers why', (tester) async {
      encrypt();
      makeDirectChat();
      await pump(tester, trust);

      expect(find.text(_unconfirmed), findsOneWidget);
      expect(why(), findsOneWidget);
    });
  }

  for (final trust in [
    UserTrustState.confirmed,
    UserTrustState.confirmedWithPendingDevice,
  ]) {
    testWidgets('a chat with someone ${trust.name} says only the two of you', (
      tester,
    ) async {
      encrypt();
      makeDirectChat();
      await pump(tester, trust);

      expect(
        find.text('$_encrypted Only you and @sam can read them.'),
        findsOneWidget,
      );
      expect(why(), findsNothing);
    });
  }

  testWidgets('someone who cannot be confirmed gets no promise and no link', (
    tester,
  ) async {
    encrypt();
    makeDirectChat();
    await pump(tester, UserTrustState.noIdentity);

    expect(find.text(_encrypted), findsOneWidget);
    expect(why(), findsNothing);
  });

  testWidgets('Why confirm opens the explanation for that person', (
    tester,
  ) async {
    encrypt();
    makeDirectChat();
    await pump(tester, UserTrustState.unconfirmed);

    await tester.tap(why());
    await tester.pumpAndSettle();

    expect(find.byType(WhyConfirmSheet), findsOneWidget);
    expect(find.text('Confirm it is really @sam'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(find.byType(WhyConfirmSheet), findsNothing);
  });

  testWidgets('before they join, it explains but says confirming waits', (
    tester,
  ) async {
    encrypt();
    makeDirectChat();
    room.summary = RoomSummary.fromJson({
      'm.heroes': [_sam],
      'm.joined_member_count': 1,
      'm.invited_member_count': 1,
    });
    await pump(tester, UserTrustState.unconfirmed);

    await tester.tap(why());
    await tester.pumpAndSettle();

    expect(find.text('You can confirm @sam once they join.'), findsOneWidget);
    expect(find.text('Confirm it is really @sam'), findsNothing);
  });
}
