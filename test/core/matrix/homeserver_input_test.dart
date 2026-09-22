import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/matrix/homeserver_input.dart';

void main() {
  Uri? uriFor(String input) => parseHomeserverInput(input).uri;
  String? errorFor(String input) => parseHomeserverInput(input).error;

  group('accepted', () {
    test('a plain hostname becomes https', () {
      expect(
        uriFor('matrix.example.org'),
        Uri.parse('https://matrix.example.org'),
      );
    });

    test('a full https address is kept as typed', () {
      expect(
        uriFor('https://matrix.example.org'),
        Uri.parse('https://matrix.example.org'),
      );
    });

    test('surrounding whitespace is trimmed, not rejected', () {
      expect(
        uriFor('  matrix.example.org  '),
        Uri.parse('https://matrix.example.org'),
      );
    });

    test('a hostname with a port', () {
      expect(
        uriFor('matrix.example.org:8448'),
        Uri.parse('https://matrix.example.org:8448'),
      );
    });

    test('a hostname with a path — a homeserver may live under one', () {
      expect(
        uriFor('matrix.example.org/matrix'),
        Uri.parse('https://matrix.example.org/matrix'),
      );
    });

    test('a trailing slash is harmless', () {
      expect(errorFor('matrix.example.org/'), isNull);
    });
  });

  group('refused, with a sentence rather than a parser dump', () {
    test('empty input asks for something', () {
      expect(errorFor('   '), isNotNull);
      expect(errorFor('   '), isNot(contains('FormatException')));
    });

    test('a pasted Matrix ID is named for what it is', () {
      final error = errorFor('@user:matrix.example.org');
      expect(error, isNotNull);
      expect(error, contains('username'));
    });

    test('spaces in the address', () {
      expect(errorFor('matrix example org'), homeserverShapeMessage);
    });

    test('nothing but a scheme', () {
      expect(errorFor('https://'), homeserverShapeMessage);
    });

    test('a broken scheme', () {
      expect(errorFor('ht!tp://matrix.example.org'), homeserverShapeMessage);
    });

    test('an empty scheme', () {
      expect(errorFor('://'), homeserverShapeMessage);
    });

    test('http is refused on its own terms, not as a shape problem', () {
      final error = errorFor('http://matrix.example.org');
      expect(error, isNotNull);
      expect(error, isNot(homeserverShapeMessage));
      expect(error, contains('https'));
    });

    test('the shape message names both accepted forms', () {
      expect(homeserverShapeMessage, contains('chat.example.org'));
      expect(homeserverShapeMessage, contains('https://'));
    });
  });

  group('a refusal never carries a parser dump', () {
    for (final input in [
      '',
      '   ',
      '://',
      'https://',
      'ht!tp://x',
      '@user:matrix.example.org',
      'matrix example org',
      'http://matrix.example.org',
    ]) {
      test('"$input"', () {
        final error = errorFor(input);
        expect(error, isNotNull);
        expect(error, isNot(contains('FormatException')));
        expect(error, isNot(contains('\n')));
        expect(error, isNot(contains('^')));
      });
    }
  });

  group('shown back as typed', () {
    for (final (uri, text) in [
      ('https://zuno.chat', 'zuno.chat'),
      ('https://matrix.example.org/', 'matrix.example.org'),
      ('https://matrix.example.org:8448', 'https://matrix.example.org:8448'),
      (
        'https://matrix.example.org/matrix',
        'https://matrix.example.org/matrix',
      ),
    ]) {
      test('$uri reads $text', () {
        expect(homeserverInputText(Uri.parse(uri)), text);
      });
    }
  });
}
