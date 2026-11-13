import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/security/security_emphasis.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/security/user_trust.dart';
import 'package:zuno/core/ui/zuno_colors.dart';
import 'package:zuno/features/rooms/presentation/room_kind_avatar.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    String? directUserId,
    UserTrustState trust = UserTrustState.unconfirmed,
    bool community = false,
    String fallbackText = 'Bob',
    String toneSeed = '@bob:example.org',
  }) async {
    final client = buildTestClient(userId: '@me:example.org');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [userTrustProvider.overrideWith((ref, _) => trust)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RoomKindAvatar(
              client: client,
              avatarUrl: null,
              fallbackText: fallbackText,
              directUserId: directUserId,
              community: community,
              toneSeed: toneSeed,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a direct chat is badged with one person', (tester) async {
    await pump(tester, directUserId: '@bob:example.org');

    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(find.byIcon(Icons.groups), findsNothing);
    expect(find.byIcon(confirmedPersonIcon), findsNothing);
  });

  testWidgets('a direct chat with a confirmed person is badged confirmed '
      'instead', (tester) async {
    await pump(
      tester,
      directUserId: '@bob:example.org',
      trust: UserTrustState.confirmed,
    );

    expect(find.byIcon(confirmedPersonIcon), findsOneWidget);
    expect(find.byIcon(Icons.person), findsNothing);
  });

  testWidgets('a group is badged with several', (tester) async {
    await pump(tester);

    expect(find.byIcon(Icons.groups), findsOneWidget);
    expect(find.byIcon(Icons.person), findsNothing);
  });

  testWidgets('a group is never badged confirmed', (tester) async {
    await pump(tester, trust: UserTrustState.confirmed);

    expect(find.byIcon(Icons.groups), findsOneWidget);
    expect(find.byIcon(confirmedPersonIcon), findsNothing);
  });

  testWidgets('the avatar underneath keeps its initials and tone', (
    tester,
  ) async {
    await pump(tester, directUserId: '@bob:example.org');

    expect(find.text('B'), findsOneWidget);
    final circle =
        tester
                .widget<DecoratedBox>(
                  find.ancestor(
                    of: find.text('B'),
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(circle.color, avatarToneFor('@bob:example.org'));
    expect(circle.shape, BoxShape.circle);
  });

  testWidgets('a community is a rounded square with no badge', (tester) async {
    await pump(
      tester,
      community: true,
      fallbackText: 'Climbing club',
      toneSeed: '!club:example.org',
    );

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
