import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/rooms/optimistic_room_state.dart';
import 'package:zuno/core/settings/matrix_experience.dart';

import '../../helpers/fake_matrix.dart';
import '../../helpers/zuno_app.dart';

void main() {
  Widget label(String Function(BuildContext context) text) =>
      Builder(builder: (context) => Text(text(context)));

  Widget idLabel(String id) => label((context) => context.matrixIdLabel(id));

  Widget addressLabel(Room room) =>
      label((context) => context.matrixRoomAddress(room) ?? 'no address');

  Room roomWithAlias(String? alias) {
    final room = buildTestRoom(buildTestClient());
    if (alias != null) {
      applyOptimisticRoomState(room, EventTypes.RoomCanonicalAlias, {
        'alias': alias,
      });
    }
    return room;
  }

  testWidgets('with the Matrix experience off, an ID drops its server', (
    tester,
  ) async {
    await tester.pumpWidget(
      inZunoApp(
        MatrixExperience(on: false, child: idLabel('#general:example.org')),
      ),
    );

    expect(find.text('#general'), findsOneWidget);
    expect(find.textContaining('example.org'), findsNothing);
  });

  testWidgets('with no app-wide choice, an ID drops its server', (
    tester,
  ) async {
    await tester.pumpWidget(inZunoApp(idLabel('@sam:example.org')));

    expect(find.text('@sam'), findsOneWidget);
  });

  testWidgets('turning the Matrix experience on redraws the IDs already '
      'shown with their server', (tester) async {
    final shown = idLabel('@sam:example.org');
    await tester.pumpWidget(
      inZunoApp(MatrixExperience(on: false, child: shown)),
    );
    await tester.pumpWidget(
      inZunoApp(MatrixExperience(on: true, child: shown)),
    );

    expect(find.text('@sam:example.org'), findsOneWidget);
  });

  testWidgets('with the Matrix experience on, a room shows its whole address', (
    tester,
  ) async {
    await tester.pumpWidget(
      inZunoApp(
        MatrixExperience(
          on: true,
          child: addressLabel(roomWithAlias('#chess:example.org')),
        ),
      ),
    );

    expect(find.text('#chess:example.org'), findsOneWidget);
  });

  testWidgets('with the Matrix experience off, a room shows no address', (
    tester,
  ) async {
    await tester.pumpWidget(
      inZunoApp(
        MatrixExperience(
          on: false,
          child: addressLabel(roomWithAlias('#chess:example.org')),
        ),
      ),
    );

    expect(find.text('no address'), findsOneWidget);
  });

  testWidgets('a room without an address shows none, even in the Matrix '
      'experience', (tester) async {
    await tester.pumpWidget(
      inZunoApp(
        MatrixExperience(on: true, child: addressLabel(roomWithAlias(null))),
      ),
    );

    expect(find.text('no address'), findsOneWidget);
  });
}
