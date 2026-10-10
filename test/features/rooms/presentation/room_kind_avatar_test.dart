import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/ui/zuno_colors.dart';
import 'package:zuno/features/rooms/presentation/room_kind_avatar.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool isDirect,
    bool community = false,
    String fallbackText = 'Bob',
    String toneSeed = '@bob:example.org',
  }) async {
    final client = buildTestClient(userId: '@me:example.org');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomKindAvatar(
            client: client,
            avatarUrl: null,
            fallbackText: fallbackText,
            isDirect: isDirect,
            community: community,
            toneSeed: toneSeed,
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

  testWidgets('the avatar underneath keeps its initials and tone', (
    tester,
  ) async {
    await pump(tester, isDirect: true);

    expect(find.text('B'), findsOneWidget);
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundColor, avatarToneFor('@bob:example.org'));
  });

  testWidgets('a community is a rounded square with no badge', (tester) async {
    await pump(
      tester,
      isDirect: false,
      community: true,
      fallbackText: 'Climbing club',
      toneSeed: '!club:example.org',
    );

    expect(find.byType(CircleAvatar), findsNothing);
    expect(find.byIcon(Icons.groups), findsNothing);
    expect(find.text('C'), findsOneWidget);
    final box = tester.widget<DecoratedBox>(
      find.ancestor(of: find.text('C'), matching: find.byType(DecoratedBox)),
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, avatarToneFor('!club:example.org'));
    expect(decoration.borderRadius, isNotNull);
  });
}
