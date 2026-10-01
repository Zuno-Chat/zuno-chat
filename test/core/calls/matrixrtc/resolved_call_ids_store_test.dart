import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_store.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('a resolved call is readable back', () async {
    await markCallResolvedOnDisk(prefs, 'call-1');
    await markCallResolvedOnDisk(prefs, 'call-2');

    expect(readResolvedCallIds(prefs), {'call-1', 'call-2'});
  });

  test('nothing stored reads as empty', () {
    expect(readResolvedCallIds(prefs), isEmpty);
  });

  test('an old resolution is pruned', () async {
    final longAgo = DateTime.now().subtract(const Duration(minutes: 10));
    await markCallResolvedOnDisk(prefs, 'stale', now: longAgo);
    await markCallResolvedOnDisk(prefs, 'fresh');

    expect(readResolvedCallIds(prefs), {'fresh'});
  });

  test('a corrupt stored value reads as empty rather than throwing', () async {
    await prefs.setString('calls.resolved', 'not json');

    expect(readResolvedCallIds(prefs), isEmpty);
  });

  test('marks from two isolates whose caches have not seen each other both '
      'survive', () async {
    SharedPreferences.resetStatic();
    final otherIsolate = await SharedPreferences.getInstance();

    await markCallResolvedOnDisk(prefs, 'from-here');
    await markCallResolvedOnDisk(otherIsolate, 'from-there');

    await prefs.reload();
    expect(readResolvedCallIds(prefs), {'from-here', 'from-there'});
  });

  group('a value stored in the single key earlier versions used', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'calls.resolved': jsonEncode({
          'old-fresh': DateTime.now().millisecondsSinceEpoch,
          'old-stale': DateTime.now()
              .subtract(const Duration(minutes: 10))
              .millisecondsSinceEpoch,
        }),
      });
      prefs = await SharedPreferences.getInstance();
    });

    test('still reads, within the same retention', () {
      expect(readResolvedCallIds(prefs), {'old-fresh'});
    });

    test('moves to one key per call on the next mark, and the old key '
        'goes', () async {
      await markCallResolvedOnDisk(prefs, 'new');

      expect(prefs.containsKey('calls.resolved'), isFalse);
      expect(readResolvedCallIds(prefs), {'old-fresh', 'new'});
    });
  });

  test('only the newest entries are kept', () async {
    final start = DateTime(2026, 9, 3, 12);
    for (var i = 0; i < 40; i++) {
      await markCallResolvedOnDisk(
        prefs,
        'call-$i',
        now: start.add(Duration(seconds: i)),
      );
    }

    final resolved = readResolvedCallIds(
      prefs,
      now: start.add(const Duration(seconds: 40)),
    );
    expect(resolved, hasLength(32));
    expect(resolved, contains('call-39'));
    expect(resolved, isNot(contains('call-0')));
  });

  group('across paths and isolates', resolvedCallsAcrossPaths);
}

void resolvedCallsAcrossPaths() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('with no one mirroring resolved calls in memory', () {
    test('a call marked resolved is read back from disk', () async {
      await markCallResolved('call-1');

      await prefs.reload();
      expect(readResolvedCallIds(prefs), {'call-1'});
      expect(await isCallResolved('call-1'), isTrue);
    });

    test('an unknown call is not resolved', () async {
      expect(await isCallResolved('call-1'), isFalse);
    });

    test('marks from two paths at once both land on disk', () async {
      await Future.wait([markCallResolved('a'), markCallResolved('b')]);

      await prefs.reload();
      expect(readResolvedCallIds(prefs), {'a', 'b'});
    });
  });

  group('with a mirror attached', () {
    late Set<String> mirrored;
    late ResolvedCallsMirror mirror;

    setUp(() {
      mirrored = {};
      mirror = ResolvedCallsMirror(
        contains: mirrored.contains,
        add: mirrored.add,
      );
      attachResolvedCallsMirror(mirror);
      addTearDown(() => detachResolvedCallsMirror(mirror));
    });

    test('a mark reaches the mirror at once, before the disk write '
        'lands', () {
      unawaited(markCallResolved('call-1'));

      expect(mirrored, {'call-1'});
    });

    test('the mirror answers for a call it knows, without disk', () async {
      mirrored.add('only-in-memory');

      expect(await isCallResolved('only-in-memory'), isTrue);
    });

    test('a call found only on disk is handed to the mirror', () async {
      await markCallResolvedOnDisk(prefs, 'from-another-isolate');

      expect(await isCallResolved('from-another-isolate'), isTrue);
      expect(mirrored, {'from-another-isolate'});
    });

    test('detaching someone else\'s mirror leaves this one attached', () async {
      detachResolvedCallsMirror(
        ResolvedCallsMirror(contains: (_) => false, add: (_) {}),
      );
      unawaited(markCallResolved('call-2'));

      expect(mirrored, {'call-2'});
    });
  });
}
