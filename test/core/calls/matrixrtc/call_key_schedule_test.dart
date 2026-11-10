import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/matrixrtc/call_key_schedule.dart';
import 'package:zuno/core/calls/matrixrtc/call_sender_key_event.dart';

const _leave = Duration(seconds: 2);
const _use = Duration(seconds: 2);
const _grace = Duration(seconds: 10);
const _maxAge = Duration(minutes: 90);

CallKeySchedule _schedule({
  void Function(SenderKey key)? onMade,
  void Function(int slot)? onUse,
}) {
  final schedule = CallKeySchedule(
    leaveDelay: _leave,
    useDelay: _use,
    joinGrace: _grace,
    maxAge: _maxAge,
    onMade: onMade ?? (_) {},
    onUse: onUse ?? (_) {},
  );
  addTearDown(schedule.dispose);
  return schedule;
}

void main() {
  late List<SenderKey> made;
  late List<int> used;
  late CallKeySchedule schedule;

  setUp(() {
    made = [];
    used = [];
    schedule = _schedule(onMade: made.add, onUse: used.add);
  });

  test('start makes gen 1 of its epoch, sent at once from slot 0', () {
    final first = schedule.start(1700);

    expect(first.epoch, 1700);
    expect(first.gen, 1);
    expect(first.key, hasLength(32));
    expect(schedule.latest, same(first));
    expect(made, isEmpty);
    expect(used, isEmpty);
  });

  test('two calls never make the same key', () {
    final other = _schedule();

    expect(schedule.start(1).key, isNot(other.start(1).key));
  });

  test('a departure before start does nothing', () {
    fakeAsync((async) {
      schedule.departed(removal: true);
      async.elapse(const Duration(seconds: 10));

      expect(made, isEmpty);
    });
  });

  test('a leave makes a key after the leave delay and uses it after the use '
      'delay', () {
    fakeAsync((async) {
      schedule.start(1);

      schedule.departed(removal: false);
      async.elapse(_leave - const Duration(milliseconds: 1));
      expect(made, isEmpty);

      async.elapse(const Duration(milliseconds: 1));
      expect([for (final key in made) key.gen], [2]);
      expect(schedule.latest?.gen, 2);
      expect(used, isEmpty);

      async.elapse(_use);
      expect(used, [1]);
    });
  });

  test('two leaves inside the leave delay make one key', () {
    fakeAsync((async) {
      schedule.start(1);

      schedule.departed(removal: false);
      async.elapse(const Duration(milliseconds: 500));
      schedule.departed(removal: false);
      async.elapse(_leave + _use);

      expect([for (final key in made) key.gen], [2]);
      expect(used, [1]);
    });
  });

  test('a removal makes a key at once, still used only after the use '
      'delay', () {
    fakeAsync((async) {
      schedule.start(1);

      schedule.departed(removal: true);
      expect([for (final key in made) key.gen], [2]);
      expect(used, isEmpty);

      async.elapse(_use);
      expect(used, [1]);
    });
  });

  test('a departure during the use delay still uses the pending key on time, '
      'then the newer one', () {
    fakeAsync((async) {
      schedule.start(1);
      schedule.departed(removal: true);
      async.elapse(const Duration(milliseconds: 500));

      schedule.departed(removal: false);
      async.elapse(_use - const Duration(milliseconds: 500));
      expect(used, [1]);

      async.elapse(_leave + _use);
      expect([for (final key in made) key.gen], [2, 3]);
      expect(used, [1, 2]);
    });
  });

  test('departures closer together than both delays never stop new keys '
      'being used', () {
    fakeAsync((async) {
      schedule.start(1);

      for (var i = 0; i < 4; i++) {
        schedule.departed(removal: true);
        async.elapse(const Duration(seconds: 1));
      }
      async.elapse(_use);

      expect(used, [1, 2, 3, 4]);
    });
  });

  test('a removal replacing a pending leave skips the rest of its wait', () {
    fakeAsync((async) {
      schedule.start(1);
      schedule.departed(removal: false);
      async.elapse(const Duration(milliseconds: 500));

      schedule.departed(removal: true);
      expect([for (final key in made) key.gen], [2]);

      async.elapse(_leave + _use);
      expect([for (final key in made) key.gen], [2]);
      expect(used, [1]);
    });
  });

  test('gen 257 sends from slot 0 again', () {
    fakeAsync((async) {
      schedule.start(1);
      for (var i = 0; i < 256; i++) {
        schedule.departed(removal: true);
        async.elapse(_use);
      }

      expect(made.last.gen, 257);
      expect(used.last, 0);
    });
  });

  test('a key nobody has received yet goes to a joiner however old it '
      'is', () {
    fakeAsync((async) {
      schedule.start(1);
      async.elapse(_grace * 3);

      schedule.joined();

      expect(made, isEmpty);
    });
  });

  test('the grace period runs from the key\'s first share, not from when it '
      'was made', () {
    fakeAsync((async) {
      final first = schedule.start(1);
      async.elapse(_grace * 2);
      schedule.shared(first);
      async.elapse(_grace - const Duration(milliseconds: 1));

      schedule.joined();
      expect(made, isEmpty);

      async.elapse(const Duration(milliseconds: 1));
      schedule.joined();
      expect([for (final key in made) key.gen], [2]);
    });
  });

  test('sharing an earlier key again does not restart the grace period', () {
    fakeAsync((async) {
      final first = schedule.start(1);
      schedule.shared(first);
      async.elapse(_grace);

      schedule.shared(first);
      schedule.joined();

      expect([for (final key in made) key.gen], [2]);
    });
  });

  test('a join while our key is younger than the grace period keeps it', () {
    fakeAsync((async) {
      schedule.shared(schedule.start(1));
      async.elapse(_grace - const Duration(milliseconds: 1));

      schedule.joined();
      async.elapse(_use);

      expect(made, isEmpty);
      expect(used, isEmpty);
    });
  });

  test('a join once our key has been shared for the grace period makes a key '
      'at once, used after the use delay', () {
    fakeAsync((async) {
      schedule.shared(schedule.start(1));
      async.elapse(_grace);

      schedule.joined();
      expect([for (final key in made) key.gen], [2]);
      expect(used, isEmpty);

      async.elapse(_use);
      expect(used, [1]);
    });
  });

  test('joins right after a join rotation share its key', () {
    fakeAsync((async) {
      schedule.shared(schedule.start(1));
      async.elapse(_grace);
      schedule.joined();
      schedule.shared(made.last);
      async.elapse(const Duration(seconds: 1));

      schedule.joined();

      expect([for (final key in made) key.gen], [2]);
    });
  });

  test('a join rotation takes over a pending leave', () {
    fakeAsync((async) {
      schedule.shared(schedule.start(1));
      async.elapse(_grace);
      schedule.departed(removal: false);

      schedule.joined();
      async.elapse(_leave + _use);

      expect([for (final key in made) key.gen], [2]);
      expect(used, [1]);
    });
  });

  test('a join before start does nothing', () {
    fakeAsync((async) {
      schedule.joined();
      async.elapse(_grace);

      expect(made, isEmpty);
    });
  });

  test('a key is replaced once it reaches its maximum age, and the new one '
      'ages from then', () {
    fakeAsync((async) {
      schedule.start(1);
      async.elapse(_maxAge - const Duration(seconds: 1));
      expect(made, isEmpty);

      async.elapse(const Duration(seconds: 1));
      expect([for (final key in made) key.gen], [2]);

      async.elapse(_maxAge - const Duration(seconds: 1));
      expect([for (final key in made) key.gen], [2]);
      async.elapse(const Duration(seconds: 1));
      expect([for (final key in made) key.gen], [2, 3]);
      expect(used, [1]);
    });
  });

  test('once disposed, nothing it is asked arms a timer', () {
    fakeAsync((async) {
      schedule.dispose();

      schedule.start(1);
      schedule.joined();
      schedule.departed(removal: true);
      schedule.departed(removal: false);

      expect(async.pendingTimers, isEmpty);
      expect(made, isEmpty);
    });
  });

  test('dispose stops a pending rotation', () {
    fakeAsync((async) {
      schedule.start(1);
      schedule.departed(removal: false);

      schedule.dispose();
      async.elapse(_maxAge);

      expect(made, isEmpty);
      expect(used, isEmpty);
    });
  });
}
