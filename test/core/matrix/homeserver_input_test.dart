import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/matrix/homeserver_input.dart';

void main() {
  Uri? uriFor(String input) => parseHomeserverInput(input).uri;
  String? errorFor(String input) => parseHomeserverInput(input).error;

  group('accepted', () {
    for (final (label, input, uri) in [
      (
        'a plain hostname becomes https',
        'matrix.example.org',
        'https://matrix.example.org',
      ),
      (
        'a full https address is kept as typed',
        'https://matrix.example.org',
        'https://matrix.example.org',
      ),
      (
        'surrounding whitespace is trimmed, not rejected',
        '  matrix.example.org  ',
        'https://matrix.example.org',
      ),
      (
        'a hostname with a port',
        'matrix.example.org:8448',
        'https://matrix.example.org:8448',
      ),
      (
        'a hostname with a path, since a homeserver may live under one',
        'matrix.example.org/matrix',
        'https://matrix.example.org/matrix',
      ),
    ]) {
      test(label, () {
        expect(uriFor(input), Uri.parse(uri));
      });
    }

    test('a trailing slash is harmless', () {
      expect(errorFor('matrix.example.org/'), isNull);
    });
  });

  group('refused, with a sentence rather than a parser dump', () {
    test('a pasted Matrix ID is named for what it is', () {
      expect(errorFor('@user:matrix.example.org'), contains('username'));
    });

    for (final (label, input) in [
      ('spaces in the address', 'matrix example org'),
      ('nothing but a scheme', 'https://'),
      ('a broken scheme', 'ht!tp://matrix.example.org'),
      ('an empty scheme', '://'),
    ]) {
      test('$label asks for a hostname or a full https address', () {
        expect(errorFor(input), homeserverShapeMessage);
      });
    }

    test('http is refused on its own terms, not as a shape problem', () {
      final error = errorFor('http://matrix.example.org');
      expect(error, isNot(homeserverShapeMessage));
      expect(error, contains('https'));
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
