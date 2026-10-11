import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/chat/presentation/message_contents/text_message.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_url_launcher.dart';
import '../../../helpers/zuno_app.dart';

void main() {
  late Room room;

  setUp(() => room = buildTestRoom(buildTestClient(userId: '@me:example.org')));

  Event formatted(String html, String body) => buildTestEvent(
    room,
    eventId: r'$m1',
    senderId: '@bob:example.org',
    content: {
      'msgtype': MessageTypes.Text,
      'body': body,
      'format': 'org.matrix.custom.html',
      'formatted_body': html,
    },
  );

  Future<void> pumpFormatted(WidgetTester tester, String html, String body) =>
      tester.pumpWidget(
        inZunoApp(
          TextMessage(
            displayEvent: formatted(html, body),
            body: body,
            meta: null,
          ),
        ),
      );

  Future<void> tapLink(WidgetTester tester, String shown) async {
    TapGestureRecognizer? recognizer;
    for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
      text.text.visitChildren((span) {
        if (span is TextSpan &&
            span.toPlainText() == shown &&
            span.recognizer is TapGestureRecognizer) {
          recognizer = span.recognizer! as TapGestureRecognizer;
        }
        return recognizer == null;
      });
    }
    recognizer!.onTap!();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a room link in formatted text opens like one in plain text', (
    tester,
  ) async {
    final launched = mockUrlLauncher(tester);
    await pumpFormatted(
      tester,
      'join <a href="https://matrix.to/#/#lobby:example.org">the lobby</a>',
      'join the lobby',
    );

    await tapLink(tester, 'the lobby');

    expect(launched, ['https://matrix.to/#/%23lobby:example.org']);
  });

  testWidgets('an email link with no email app says so instead of failing', (
    tester,
  ) async {
    mockUrlLauncher(
      tester,
      answer: () async => throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
    );
    await pumpFormatted(
      tester,
      '<a href="mailto:a@example.org">write to us</a>',
      'write to us',
    );

    final reports = await reportsDuring(() => tapLink(tester, 'write to us'));

    expect(reports, isEmpty);
    expect(
      find.text('Email not opened. Write to a@example.org from your email.'),
      findsOneWidget,
    );
  });

  testWidgets('a mention pill shows the name, not a link', (tester) async {
    await pumpFormatted(
      tester,
      '<b>hi</b> <a href="https://matrix.to/#/@alice:example.org" title="a>b">'
          '@alice:example.org</a>',
      'hi @alice',
    );

    expect(find.textContaining('@alice', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('example.org', findRichText: true),
      findsNothing,
    );
    expect(find.textContaining('b">', findRichText: true), findsNothing);
  });
}
