import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/security/unverified_device_warning_provider.dart';
import 'package:zuno/features/chat/presentation/unvouched_device_banner.dart';

import '../../../helpers/fake_matrix.dart';

class _Flagged extends UnvouchedDeviceWarningNotifier {
  final Set<String> ids;

  _Flagged(this.ids);

  @override
  Set<String> build() => ids;
}

void main() {
  late Client client;
  late Room room;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
    for (final id in ['@me:example.org', '@bob:example.org']) {
      room.setState(User(id, membership: 'join', room: room));
    }
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    ProviderScope(
      overrides: [
        unvouchedDeviceWarningProvider.overrideWith(
          () => _Flagged({'@bob:example.org'}),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(body: UnvouchedDeviceBanner(room: room)),
      ),
    ),
  );

  testWidgets('warns in a private room', (tester) async {
    await pump(tester);

    expect(find.textContaining('signed in on a new device'), findsOneWidget);
  });

  testWidgets('stays silent in a public room', (tester) async {
    room.setState(
      buildTestEvent(
        room,
        eventId: r'$join',
        senderId: '@me:example.org',
        type: EventTypes.RoomJoinRules,
        stateKey: '',
        content: {'join_rule': 'public'},
      ),
    );
    await pump(tester);

    expect(find.textContaining('signed in on a new device'), findsNothing);
  });
}
