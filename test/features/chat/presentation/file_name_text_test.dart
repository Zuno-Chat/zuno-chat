import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/features/chat/presentation/file_name_text.dart';

void main() {
  group('splitFileExtension', () {
    test('splits at the last dot', () {
      expect(splitFileExtension('report.pdf'), (base: 'report', extension: '.pdf'));
      expect(
        splitFileExtension('archive.tar.gz'),
        (base: 'archive.tar', extension: '.gz'),
      );
    });

    test('leaves names without an extension whole', () {
      expect(splitFileExtension('README'), (base: 'README', extension: ''));
      expect(splitFileExtension('notes.'), (base: 'notes.', extension: ''));
    });

    test('leaves dotfiles whole', () {
      expect(splitFileExtension('.bashrc'), (base: '.bashrc', extension: ''));
    });

    test('treats an overlong suffix as part of the name, not an extension',
        () {
      expect(
        splitFileExtension('a.verylongsuffixthatisnotanextension'),
        (base: 'a.verylongsuffixthatisnotanextension', extension: ''),
      );
    });
  });

  group('FileNameText', () {
    testWidgets('keeps the extension visible when the name is too long',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              child: FileNameText('a-very-long-quarterly-report-final.pdf'),
            ),
          ),
        ),
      );

      final extension = tester.widget<Text>(find.text('.pdf'));
      expect(extension.overflow, isNot(TextOverflow.ellipsis));
      final base = tester.widget<Text>(
        find.text('a-very-long-quarterly-report-final'),
      );
      expect(base.overflow, TextOverflow.ellipsis);
      expect(base.maxLines, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders a name without an extension as one text',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: FileNameText('README'))),
      );

      expect(find.text('README'), findsOneWidget);
      expect(find.byType(Text), findsOneWidget);
    });
  });
}
