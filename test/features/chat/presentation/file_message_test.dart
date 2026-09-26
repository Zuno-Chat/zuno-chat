import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/file_name_text.dart';
import 'package:zuno/features/chat/presentation/message_contents/file_message.dart';
import 'package:zuno/features/chat/presentation/message_meta.dart';

import '../../../helpers/fake_attachments.dart';
import '../../../helpers/fake_matrix.dart';

const _meta = MessageMeta(time: '09:41', own: false);

void main() {
  late AttachmentServer server;
  late DeviceFakes device;

  setUp(() {
    server = installAttachmentServer();
    device = installDeviceFakes();
  });

  Event file({
    String body = 'report.pdf',
    String? filename,
    int? size = 2048,
  }) => buildTestEvent(
    server.room,
    eventId: r'$file',
    senderId: '@bob:example.org',
    status: EventStatus.synced,
    content: {
      'msgtype': MessageTypes.File,
      'body': body,
      'filename': ?filename,
      'url': 'mxc://example.org/file',
      'info': {'mimetype': 'application/pdf', 'size': ?size},
    },
  );

  Future<void> pumpFile(WidgetTester tester, Event event) => tester.pumpWidget(
    MaterialApp(
      theme: zunoLightTheme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 280,
            child: FileMessage(event: event, own: false, meta: _meta),
          ),
        ),
      ),
    ),
  );

  Future<void> saveBy(WidgetTester tester, {bool Function()? until}) async {
    await tester.tap(find.byType(InkWell));
    await pumpWhileFetching(
      tester,
      rounds: 40,
      until: until ?? () => find.byType(SnackBar).evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 750));
  }

  String shownName(WidgetTester tester) =>
      tester.widget<FileNameText>(find.byType(FileNameText)).name;

  testWidgets('shows the file name and its size', (tester) async {
    await pumpFile(tester, file());

    expect(shownName(tester), 'report.pdf');
    expect(find.text('2.0 KB'), findsOneWidget);
  });

  testWidgets('a file of unknown size shows no size', (tester) async {
    await pumpFile(tester, file(size: null));

    expect(find.textContaining('KB'), findsNothing);
    expect(find.byType(MessageMeta), findsOneWidget);
  });

  testWidgets('a captioned file shows its real name, then the caption', (
    tester,
  ) async {
    await pumpFile(
      tester,
      file(body: 'Numbers for Q3', filename: 'report.pdf'),
    );

    expect(shownName(tester), 'report.pdf');
    expect(find.text('Numbers for Q3'), findsOneWidget);
  });

  testWidgets('tapping it saves it through the save dialog', (tester) async {
    await pumpFile(tester, file());

    await saveBy(tester);

    final saved = device.picker.saved.single;
    expect(saved.fileName, 'report.pdf');
    expect(saved.mimeType, 'application/pdf');
    expect(saved.bytes, server.served);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('a name that tries to leave its folder is saved as just the '
      'name', (tester) async {
    await pumpFile(tester, file(body: '../../../etc/report.pdf'));

    await saveBy(tester);

    expect(device.picker.saved.single.fileName, 'report.pdf');
  });

  testWidgets('saving it again does not download it again', (tester) async {
    await pumpFile(tester, file());
    await saveBy(tester);
    await tester.pump(const Duration(seconds: 5));

    await saveBy(tester, until: () => device.picker.saved.length == 2);

    expect(device.picker.saved, hasLength(2));
    expect(server.downloads, hasLength(1));
  });

  testWidgets('closing the save dialog says nothing', (tester) async {
    device.picker.answer = null;
    await pumpFile(tester, file());

    await saveBy(tester, until: () => device.picker.saved.isNotEmpty);

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a file that cannot be fetched says so', (tester) async {
    final event = file();
    server.goneFromServer(event);
    await pumpFile(tester, event);

    await saveBy(tester);

    expect(find.text('Could not save. Try again.'), findsOneWidget);
    expect(device.picker.saved, isEmpty);
  });

  testWidgets('shows a spinner while it saves, and ignores more taps', (
    tester,
  ) async {
    await pumpFile(tester, file());

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);

    await saveBy(tester, until: () => device.picker.saved.isNotEmpty);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
