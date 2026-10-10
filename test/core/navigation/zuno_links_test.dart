import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/navigation/zuno_links.dart';

void main() {
  group('linkNotOpenedMessage', () {
    for (final (name, uri, address) in [
      ('names a page by host and path', privacyPolicyUri, 'zuno.chat/privacy'),
      ('keeps the part after #', donateUri, 'zuno.chat/#donate'),
      (
        'names another site the same way',
        sourceCodeUri,
        'github.com/Zuno-Chat/zuno-chat',
      ),
    ]) {
      test(name, () {
        expect(
          linkNotOpenedMessage(uri),
          'Link not opened. Visit $address in a browser.',
        );
      });
    }
  });

  group('openLink', () {
    Future<void> tapLink(WidgetTester tester, UrlOpener openUrl) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => openLink(context, termsUri, openUrl: openUrl),
                child: const Text('Terms'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Terms'));
      await tester.pump();
      await tester.pump();
    }

    const notOpened = 'Link not opened. Visit zuno.chat/terms in a browser.';

    testWidgets('opens the link and says nothing', (tester) async {
      final opened = <Uri>[];
      await tapLink(tester, (uri) async {
        opened.add(uri);
        return true;
      });

      expect(opened, [termsUri]);
      expect(find.byType(SnackBar), findsNothing);
    });

    for (final (name, UrlOpener openUrl) in [
      ('says where to go when no browser opens it', (_) async => false),
      (
        'says where to go when opening it throws',
        (_) async => throw Exception('no handler'),
      ),
    ]) {
      testWidgets(name, (tester) async {
        await tapLink(tester, openUrl);

        expect(find.text(notOpened), findsOneWidget);
      });
    }
  });
}
