import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _manifest() =>
    File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

String _openingTag(String element, {String? name}) {
  final named = name == null ? '' : '[^>]*android:name="$name"';
  final tag = RegExp('<$element\\b$named[^>]*>').firstMatch(_manifest());
  if (tag == null) fail('<$element ${name ?? ''}> is not in the main manifest');
  return tag[0]!;
}

void main() {
  test(
    'MainActivity keeps the app task affinity, so Recents shows one Zuno',
    () {
      expect(
        _openingTag('activity', name: r'\.MainActivity'),
        isNot(contains('android:taskAffinity')),
      );
    },
  );

  test('the application sets no task affinity that would null every task', () {
    expect(_openingTag('application'), isNot(contains('android:taskAffinity')));
  });

  test('ShareActivity never roots or joins the Zuno task', () {
    final tag = _openingTag('activity', name: r'\.ShareActivity');
    expect(tag, contains('android:taskAffinity=""'));
    expect(tag, contains('android:excludeFromRecents="true"'));
  });
}
