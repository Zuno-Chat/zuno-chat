import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/ui/timeline_pill.dart';
import 'package:zuno/features/chat/presentation/room_update_tile.dart';

import '../../../helpers/layout_matrix.dart';

void main() {
  testWidgets('every line shows as its own pill', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RoomUpdateTile(lines: ['Sam joined', 'Lee left'])),
      ),
    );

    expect(find.byType(TimelinePill), findsNWidgets(2));
    expect(find.text('Sam joined'), findsOneWidget);
    expect(find.text('Lee left'), findsOneWidget);
  });

  testWidgets('a long update is cut to three lines', (tester) async {
    final name = 'Weekend hikes around Lisbon. ' * 40;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomUpdateTile(
            lines: ['Alex changed the room name to "$name"'],
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.maxLines, 3);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('the longest updates wrap in every language', (tester) async {
    await expectSurvivesLayoutMatrix(
      tester,
      () => Scaffold(
        body: Builder(
          builder: (context) {
            final l10n = context.l10n;
            final people = l10n.matrixPeopleMany(
              'Alexandra Montgomery-Whitfield',
              'Bartholomew Fitzgerald',
              12,
            );
            return ListView(
              children: [
                RoomUpdateTile(
                  lines: [
                    l10n.matrixStateInviteWithdrawn(
                      'Maximilian Rosenthal',
                      people,
                      14,
                    ),
                    l10n.matrixStateMadeModerator(
                      'Maximilian Rosenthal',
                      people,
                      14,
                    ),
                    l10n.matrixStateJoinedAndLeft(people, 14),
                    l10n.matrixStateNameChanged(
                      'Maximilian Rosenthal',
                      'Weekend hikes in and around Lisbon, every Saturday',
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  });
}
