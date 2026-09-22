import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/message_actions_sheet.dart';

void main() {
  Future<Future<MessageAction?>> open(
    WidgetTester tester, {
    bool canPost = true,
    bool canEdit = true,
    bool canDelete = true,
    bool isOwn = true,
    List<Widget> facts = const [Text('Sent 20 Sep, 09:30')],
    void Function(String key)? onReact,
  }) async {
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        theme: zunoLightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              host = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    final result = showMessageActionsSheet(
      host,
      canPost: canPost,
      canEdit: canEdit,
      canDelete: canDelete,
      isOwn: isOwn,
      isTextMessage: true,
      isAttachment: false,
      galleryCount: 0,
      facts: facts,
      onReact: onReact ?? (_) {},
      onMoreReactions: () {},
    );
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('the sheet orders reactions, actions, facts', (tester) async {
    await open(tester);

    final reaction = tester.getTopLeft(find.text('👍')).dy;
    final reply = tester.getTopLeft(find.text('Reply')).dy;
    final delete = tester.getTopLeft(find.text('Delete')).dy;
    final facts = tester.getTopLeft(find.text('Sent 20 Sep, 09:30')).dy;
    expect(reaction, lessThan(reply));
    expect(reply, lessThan(delete));
    expect(delete, lessThan(facts));

    final deleteText = tester.widget<Text>(find.text('Delete'));
    expect(deleteText.style!.color, zunoLightTheme.colorScheme.error);
  });

  testWidgets(
    'without permission to post there are no reactions, Reply or Edit',
    (tester) async {
      await open(tester, canPost: false, canEdit: false);

      expect(find.text('👍'), findsNothing);
      expect(find.text('Reply'), findsNothing);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    },
  );

  testWidgets('choosing an action closes the sheet with it', (tester) async {
    final result = await open(
      tester,
      canEdit: false,
      canDelete: false,
      isOwn: false,
      facts: const [],
    );
    expect(find.text('Report'), findsOneWidget);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(await result, MessageAction.copy);
  });

  testWidgets('a reaction closes the sheet, then reacts', (tester) async {
    final picked = <String>[];
    final result = await open(tester, onReact: picked.add);

    await tester.tap(find.text('❤️'));
    await tester.pumpAndSettle();

    expect(picked, ['❤️']);
    expect(await result, isNull);
    expect(find.text('Reply'), findsNothing);
  });
}
