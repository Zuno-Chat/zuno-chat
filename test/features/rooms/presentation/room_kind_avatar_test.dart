import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/ui/zuno_colors.dart';
import 'package:zuno/features/rooms/presentation/room_kind_avatar.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required bool isDirect}) async {
    final client = buildTestClient(userId: '@me:example.org');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomKindAvatar(
            client: client,
            avatarUrl: null,
            fallbackText: 'Bob',
            isDirect: isDirect,
          ),
        ),
      ),
    );
  }

  testWidgets('a direct chat is badged with one person', (tester) async {
    await pump(tester, isDirect: true);

    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(find.byIcon(Icons.groups), findsNothing);
  });

  testWidgets('a group is badged with several', (tester) async {
    await pump(tester, isDirect: false);

    expect(find.byIcon(Icons.groups), findsOneWidget);
    expect(find.byIcon(Icons.person), findsNothing);
  });

  testWidgets('the badge is filled, not the outlined chrome variant', (
    tester,
  ) async {
    await pump(tester, isDirect: true);

    expect(find.byIcon(Icons.person_outline), findsNothing);
  });

  testWidgets('the avatar still shows its initials underneath', (tester) async {
    await pump(tester, isDirect: true);

    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('the tone seed reaches the avatar', (tester) async {
    final client = buildTestClient(userId: '@me:example.org');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomKindAvatar(
            client: client,
            avatarUrl: null,
            fallbackText: 'Bob',
            isDirect: true,
            toneSeed: '@bob:example.org',
          ),
        ),
      ),
    );

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundColor, avatarToneFor('@bob:example.org'));
  });
}
