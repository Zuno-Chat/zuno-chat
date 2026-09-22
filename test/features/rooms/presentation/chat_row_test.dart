import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/event_display.dart';
import 'package:zuno/core/security/security_emphasis.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/rooms/data/chat_row_data.dart';
import 'package:zuno/features/rooms/presentation/chat_row.dart';

import '../../../helpers/fake_matrix.dart';

ChatRowData data({
  int unread = 0,
  bool muted = false,
  bool encrypted = true,
  bool awaitingAcceptance = false,
  bool partnerLeft = false,
  String? typingText,
  String timeLabel = '09:41',
}) => ChatRowData(
  roomId: '!room:example.org',
  title: 'Maya',
  avatarUrl: null,
  isDirect: true,
  toneSeed: '@maya:example.org',
  lastEventId: r'$e',
  lastEventStatus: EventStatus.synced,
  previewKind: MessageKind.text,
  previewText: 'See you at seven',
  typingText: typingText,
  timeLabel: timeLabel,
  unread: unread,
  muted: muted,
  encrypted: encrypted,
  awaitingAcceptance: awaitingAcceptance,
  pendingInviteSubtitle: awaitingAcceptance ? 'Waiting for Maya to join' : null,
  partnerLeft: partnerLeft,
  official: false,
);

void main() {
  final scheme = zunoLightTheme.colorScheme;
  late Client client;

  setUp(() => client = buildTestClient(userId: '@me:example.org'));

  Future<void> pump(
    WidgetTester tester,
    ChatRowData row, {
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: zunoLightTheme,
      home: Scaffold(
        body: ChatRow(
          data: row,
          client: client,
          preview: const Text('See you at seven'),
          onTap: onTap,
          onLongPress: onLongPress,
        ),
      ),
    ),
  );

  Text nameText(WidgetTester tester) => tester.widget<Text>(find.text('Maya'));

  testWidgets('shows the name, the preview, the time and the count', (
    tester,
  ) async {
    await pump(tester, data(unread: 2));

    expect(nameText(tester).style!.color, scheme.onSurface);
    expect(find.text('See you at seven'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    final time = tester.widget<Text>(find.text('09:41'));
    expect(time.style!.fontWeight, FontWeight.w700);
    expect(time.style!.color, scheme.onSurface);
  });

  testWidgets('without unread, the time is quiet and there is no count', (
    tester,
  ) async {
    await pump(tester, data());

    final time = tester.widget<Text>(find.text('09:41'));
    expect(time.style!.fontWeight, FontWeight.w500);
    expect(time.style!.color, scheme.onSurfaceVariant);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('a muted row dims by color, and its count is an outline', (
    tester,
  ) async {
    await pump(tester, data(unread: 12, muted: true));

    expect(nameText(tester).style!.color, scheme.onSurfaceVariant);
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
    final pill = tester.widget<Container>(
      find
          .ancestor(of: find.text('12'), matching: find.byType(Container))
          .first,
    );
    final decoration = pill.decoration! as BoxDecoration;
    expect(decoration.color, isNull);
    expect(decoration.border, isNotNull);
    expect(find.byType(Opacity), findsNothing);
  });

  testWidgets('an unmuted count is the amber fill', (tester) async {
    await pump(tester, data(unread: 5));

    final pill = tester.widget<Container>(
      find.ancestor(of: find.text('5'), matching: find.byType(Container)).first,
    );
    expect((pill.decoration! as BoxDecoration).color, scheme.primaryContainer);
  });

  testWidgets('typing replaces the preview, in amber italic', (tester) async {
    await pump(tester, data(typingText: 'typing…'));

    final typing = tester.widget<Text>(find.text('typing…'));
    expect(typing.style!.color, scheme.primary);
    expect(typing.style!.fontStyle, FontStyle.italic);
    expect(find.text('See you at seven'), findsNothing);
  });

  testWidgets('waiting for acceptance shows its status, dimmed', (
    tester,
  ) async {
    await pump(tester, data(awaitingAcceptance: true, timeLabel: ''));

    expect(find.text('Waiting for Maya to join'), findsOneWidget);
    expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);
    expect(nameText(tester).style!.color, scheme.onSurfaceVariant);
    expect(find.text('See you at seven'), findsNothing);
  });

  testWidgets('a partner who left shows its status, dimmed', (tester) async {
    await pump(tester, data(partnerLeft: true));

    expect(find.text('Left the chat'), findsOneWidget);
    expect(find.byIcon(Icons.person_off_outlined), findsOneWidget);
    expect(nameText(tester).style!.color, scheme.onSurfaceVariant);
  });

  testWidgets('a room that is not encrypted is marked in red', (tester) async {
    await pump(tester, data(encrypted: false));

    final icon = tester.widget<Icon>(find.byIcon(notEncryptedIcon));
    expect(icon.color, scheme.error);
  });

  testWidgets('every line is strut-locked, so no script makes a row taller', (
    tester,
  ) async {
    await pump(tester, data());
    expect(nameText(tester).strutStyle?.forceStrutHeight, isTrue);

    await pump(tester, data(typingText: 'typing…'));
    final typing = tester.widget<Text>(find.text('typing…'));
    expect(typing.strutStyle?.forceStrutHeight, isTrue);

    await pump(tester, data(partnerLeft: true));
    final status = tester.widget<Text>(find.text('Left the chat'));
    expect(status.strutStyle?.forceStrutHeight, isTrue);
  });

  testWidgets('tap and long-press fire', (tester) async {
    var taps = 0;
    var presses = 0;
    await pump(
      tester,
      data(),
      onTap: () => taps++,
      onLongPress: () => presses++,
    );

    await tester.tap(find.byType(ChatRow));
    await tester.longPress(find.byType(ChatRow));

    expect(taps, 1);
    expect(presses, 1);
  });

  testWidgets('every row is the same height, whatever it shows', (
    tester,
  ) async {
    await pump(tester, data());
    final plain = tester.getSize(find.byType(ChatRow)).height;
    await pump(tester, data(unread: 12, muted: true, encrypted: false));
    final busy = tester.getSize(find.byType(ChatRow)).height;
    await pump(tester, ChatRowData.prototype);
    final prototype = tester.getSize(find.byType(ChatRow)).height;

    expect(busy, plain);
    expect(prototype, plain);
    expect(plain, 72);
  });
}
