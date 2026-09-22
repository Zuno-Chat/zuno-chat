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
}
