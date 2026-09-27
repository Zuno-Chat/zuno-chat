import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/security/security_emphasis.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/security/user_trust.dart';
import 'package:zuno/features/chat/presentation/identity_change_banner.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
    client.rooms.add(room);
    for (final (id, membership) in [
      ('@me:example.org', 'join'),
      ('@bob:example.org', 'join'),
      ('@carol:example.org', 'invite'),
      ('@dave:example.org', 'leave'),
    ]) {
      room.setState(User(id, membership: membership, room: room));
    }
  });

  Future<void> pump(
    WidgetTester tester,
    Map<String, UserTrustState> trust,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixClientProvider.overrideWithValue(client),
          userTrustProvider.overrideWith(
            (ref, userId) => trust[userId] ?? UserTrustState.confirmed,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: IdentityChangeBanner(room: room)),
        ),
      ),
    );
  }

  testWidgets('says nothing while everyone is as confirmed', (tester) async {
    await pump(tester, const {});

    expect(find.byType(AttentionStripe), findsNothing);
    expect(find.text('Confirm'), findsNothing);
  });

  testWidgets('names the one person whose details changed', (tester) async {
    await pump(tester, {'@bob:example.org': UserTrustState.identityChanged});

    expect(find.byType(AttentionStripe), findsOneWidget);
    expect(find.text("@bob's security details changed"), findsOneWidget);
    expect(find.textContaining('someone is listening in'), findsOneWidget);
  });

  testWidgets('counts several, invited people included', (tester) async {
    await pump(tester, {
      '@bob:example.org': UserTrustState.identityChanged,
      '@carol:example.org': UserTrustState.identityChanged,
    });

    expect(find.text("2 people's security details changed"), findsOneWidget);
  });

  testWidgets('ignores you and people who left', (tester) async {
    await pump(tester, {
      '@me:example.org': UserTrustState.identityChanged,
      '@dave:example.org': UserTrustState.identityChanged,
    });

    expect(find.byType(AttentionStripe), findsNothing);
  });

  testWidgets('Confirm starts confirming that person', (tester) async {
    await pump(tester, {'@bob:example.org': UserTrustState.identityChanged});

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('Set up recovery first'), findsOneWidget);
  });
}
