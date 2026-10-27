import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/attachment_feedback.dart';

import '../../helpers/fake_attachments.dart';

void main() {
  late AttachmentServer server;
  late DeviceFakes device;

  setUp(() {
    server = installAttachmentServer();
    device = installDeviceFakes();
  });

  Future<ScaffoldMessengerState> pumpMessenger(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(),
      ),
    );
    return tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> save(WidgetTester tester, List<Event> events) async {
    final messenger = await pumpMessenger(tester);
    await tester.runAsync(
      () =>
          saveAttachmentsWithFeedback(messenger, englishLocalizations, events),
    );
    await settle(tester);
  }

  Future<void> share(WidgetTester tester, Event event) async {
    final messenger = await pumpMessenger(tester);
    await tester.runAsync(
      () => shareAttachmentsWithFeedback(messenger, englishLocalizations, [
        event,
      ]),
    );
    await settle(tester);
  }

  Event document() => server.attachment(
    eventId: r'$document',
    msgtype: MessageTypes.File,
    body: 'report.pdf',
    mimetype: 'application/pdf',
  );

  testWidgets('Save says where the attachment went', (tester) async {
    await save(tester, [server.attachment()]);

    expect(find.text('Saved to Photos'), findsOneWidget);
  });

  testWidgets('a save that fails says so', (tester) async {
    device.galleryRefuses = true;
    await save(tester, [server.attachment()]);

    expect(find.text('Could not save. Try again.'), findsOneWidget);
  });

  testWidgets('saving several says how many made it', (tester) async {
    final gone = server.attachment(eventId: r'$gone');
    server.goneFromServer(gone);

    await save(tester, [server.attachment(eventId: r'$kept'), gone]);

    expect(find.text('Saved 1 of 2'), findsOneWidget);
  });

  testWidgets('closing the save dialog shows nothing', (tester) async {
    device.exportAnswer = false;
    await save(tester, [document()]);

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Share opens the share sheet and clears the preparing note', (
    tester,
  ) async {
    await share(tester, server.attachment());
    await tester.pumpAndSettle();

    expect(device.shared, hasLength(1));
    expect(find.text('Preparing to share…'), findsNothing);
  });

  testWidgets('a share that fails says so', (tester) async {
    final event = server.attachment();
    server.goneFromServer(event);
    await share(tester, event);
    await tester.pumpAndSettle();

    expect(device.shared, isEmpty);
    expect(find.text('Could not share. Try again.'), findsOneWidget);
  });
}
