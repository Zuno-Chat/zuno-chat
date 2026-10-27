import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/video_viewer_page.dart';
import 'package:zuno/core/ui/zuno_theme.dart';

import '../../helpers/fake_attachments.dart';
import '../../helpers/pump_until.dart';

void main() {
  late AttachmentServer server;

  setUp(() => server = installAttachmentServer());

  testWidgets('a video that did not load says so, and Try again loads it '
      'again', (tester) async {
    final event = server.attachment(
      msgtype: MessageTypes.Video,
      body: 'clip.mp4',
      mimetype: 'video/mp4',
    );
    server.goneFromServer(event);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: zunoLightTheme,
        home: VideoViewerPage(event: event),
      ),
    );
    await pumpUntil(
      tester,
      () => shows('Video did not load.'),
      reason: 'the download to fail',
    );

    await tester.tap(find.text('Try again'));
    await pumpUntil(
      tester,
      () => server.downloads.length == 2,
      reason: 'the second download',
    );
  });
}
