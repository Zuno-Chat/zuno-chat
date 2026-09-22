import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/room_info/presentation/room_permissions_page.dart';

import '../../../helpers/card_layout.dart';
import '../../../helpers/fake_matrix.dart';

void main() {
  late Room room;

  setUp(() {
    final client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
  });

  void setOwnLevel(int level) {
    room.setState(
      StrippedStateEvent(
        type: EventTypes.RoomPowerLevels,
        senderId: '@owner:example.org',
        stateKey: '',
        content: {
          'users': {'@owner:example.org': 100, '@me:example.org': level},
        },
      ),
    );
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: RoomPermissionsPage(room: room)));
    await tester.pump();
  }

  ListTile row(WidgetTester tester, String title) =>
      tester.widget<ListTile>(find.widgetWithText(ListTile, title));

  testWidgets('every permission sits on a card', (tester) async {
    setOwnLevel(100);
    await pumpPage(tester);

    expectEveryRowOnACard();
  });

  testWidgets('an admin can change a permission and sees no notice', (
    tester,
  ) async {
    setOwnLevel(100);
    await pumpPage(tester);

    expect(row(tester, 'Change room name').onTap, isNotNull);
    expect(find.textContaining('Only admins can change these'), findsNothing);
  });

  testWidgets('a moderator only views, and is told why', (tester) async {
    setOwnLevel(50);
    await pumpPage(tester);

    expect(row(tester, 'Change room name').onTap, isNull);
    expect(
      find.text('Only admins can change these. You can view them here.'),
      findsOneWidget,
    );
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('the notice goes away when dismissed', (tester) async {
    setOwnLevel(50);
    await pumpPage(tester);

    await tester.tap(find.text('Dismiss'));
    await tester.pump();

    expect(find.textContaining('Only admins can change these'), findsNothing);
    expect(find.text('Change room name'), findsOneWidget);
  });
}
