import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/attachment_action_buttons.dart';

import '../../helpers/fake_attachments.dart';

void main() {
  late AttachmentServer server;
  late DeviceFakes device;

  setUp(() {
    server = installAttachmentServer();
    device = installDeviceFakes();
  });

  Future<void> pumpButtons(WidgetTester tester, Event event) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AttachmentActionButtons(event: event)),
        ),
      );

  Future<void> press(WidgetTester tester, String tooltip) async {
    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ),
    );
    await tester.runAsync(() => button.onPressed!.call() as dynamic);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Event document() => server.attachment(
    eventId: r'$document',
    msgtype: MessageTypes.File,
    body: 'report.pdf',
    mimetype: 'application/pdf',
  );

  testWidgets('Save says where the attachment went', (tester) async {
    await pumpButtons(tester, server.attachment());

    await press(tester, 'Save');

    expect(find.text('Saved to Photos'), findsOneWidget);
  });

  testWidgets('a save that fails says so', (tester) async {
    device.galleryRefuses = true;
    await pumpButtons(tester, server.attachment());

    await press(tester, 'Save');

    expect(find.text('Could not save. Try again.'), findsOneWidget);
  });

  testWidgets('saving several says how many made it', (tester) async {
    final gone = server.attachment(eventId: r'$gone');
    server.goneFromServer(gone);
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final messenger = tester.state<ScaffoldMessengerState>(
      find.byType(ScaffoldMessenger),
    );

    await tester.runAsync(
      () => saveAttachmentsWithFeedback(messenger, [
        server.attachment(eventId: r'$kept'),
        gone,
      ]),
    );
    await tester.pump();

    expect(find.text('Saved 1 of 2'), findsOneWidget);
  });

  testWidgets('closing the save dialog shows nothing', (tester) async {
    device.picker.answer = null;
    await pumpButtons(tester, document());

    await press(tester, 'Save');

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Share opens the share sheet and clears the preparing note', (
    tester,
  ) async {
    await pumpButtons(tester, server.attachment());

    await press(tester, 'Share');
    await tester.pumpAndSettle();

    expect(device.shared, hasLength(1));
    expect(find.text('Preparing to share…'), findsNothing);
  });

  testWidgets('a share that fails says so', (tester) async {
    final event = server.attachment();
    server.goneFromServer(event);
    await pumpButtons(tester, event);

    await press(tester, 'Share');
    await tester.pumpAndSettle();

    expect(device.shared, isEmpty);
    expect(find.text('Could not share. Try again.'), findsOneWidget);
  });
}
