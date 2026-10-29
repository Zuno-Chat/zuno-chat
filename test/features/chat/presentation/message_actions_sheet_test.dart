import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/forward_icon.dart';
import 'package:zuno/features/chat/presentation/message_actions_sheet.dart';

void main() {
  Future<Future<MessageAction?>> open(
    WidgetTester tester, {
    bool canRespond = true,
    bool canEdit = true,
    bool canDelete = true,
    bool isOwn = true,
    bool isAttachment = false,
    int galleryCount = 0,
    int forwardCount = 0,
    List<Widget> facts = const [Text('Sent 20 Sep, 09:30')],
    void Function(String key)? onReact,
  }) async {
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
      canRespond: canRespond,
      canEdit: canEdit,
      canDelete: canDelete,
      isOwn: isOwn,
      canCopy: !isAttachment,
      isAttachment: isAttachment,
      galleryCount: galleryCount,
      forwardCount: forwardCount,
      facts: facts,
      onReact: onReact ?? (_) {},
      onMoreReactions: () {},
    );
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets(
    'the sheet orders reactions, actions, facts; no Report on your own',
    (tester) async {
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
      expect(find.text('Report'), findsNothing);
    },
  );

  testWidgets(
    'when it cannot be answered there are no reactions, Reply or Edit',
    (tester) async {
      await open(tester, canRespond: false, canEdit: false);

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

  testWidgets('a gallery offers to share, save and delete all of it', (
    tester,
  ) async {
    final result = await open(tester, isAttachment: true, galleryCount: 3);

    expect(find.text('Share all (3)'), findsOneWidget);
    expect(find.text('Save all (3)'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);

    await tester.tap(find.text('Delete all (3)'));
    await tester.pumpAndSettle();
    expect(await result, MessageAction.delete);
  });

  testWidgets('one forwardable item offers Forward, several Forward all', (
    tester,
  ) async {
    final result = await open(tester, isAttachment: true, forwardCount: 1);
    expect(find.widgetWithText(ListTile, 'Forward'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Forward'),
        matching: find.byType(ForwardIcon),
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(ListTile, 'Forward'));
    await tester.pumpAndSettle();
    expect(await result, MessageAction.forward);

    await open(tester, isAttachment: true, galleryCount: 3, forwardCount: 3);
    expect(find.widgetWithText(ListTile, 'Forward all (3)'), findsOneWidget);
  });

  testWidgets('nothing forwardable offers no Forward', (tester) async {
    await open(tester, isAttachment: true);

    expect(find.textContaining('Forward'), findsNothing);
  });

  testWidgets('Forward sits right above Share', (tester) async {
    await open(tester, isAttachment: true, forwardCount: 1);

    final forward = tester.getTopLeft(find.text('Forward')).dy;
    final share = tester.getTopLeft(find.text('Share')).dy;
    final reply = tester.getTopLeft(find.text('Reply')).dy;
    expect(reply, lessThan(forward));
    expect(forward, lessThan(share));
  });
}
