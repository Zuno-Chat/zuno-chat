import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/media/reconnect_policy.dart';

void main() {
  group('DisconnectGrace', () {
    test('runs once the grace has passed', () {
      fakeAsync((async) {
        final grace = DisconnectGrace();
        var expired = 0;

        grace.start(() => expired++);
        async.elapse(reconnectGrace - const Duration(milliseconds: 1));
        expect(expired, 0);
        async.elapse(const Duration(milliseconds: 1));

        expect(expired, 1);
      });
    });

    test('a second start while it runs keeps the first deadline and '
        'action', () {
      fakeAsync((async) {
        final grace = DisconnectGrace();
        final expired = <String>[];

        grace.start(() => expired.add('first'));
        async.elapse(const Duration(seconds: 3));
        grace.start(() => expired.add('second'));
        async.elapse(const Duration(seconds: 2));

        expect(expired, ['first']);
        async.elapse(reconnectGrace);
        expect(expired, ['first']);
      });
    });

    test('a cancel stops it, and a later start runs a fresh grace', () {
      fakeAsync((async) {
        final grace = DisconnectGrace();
        final expired = <String>[];

        grace.start(() => expired.add('cancelled'));
        grace.cancel();
        async.elapse(reconnectGrace);
        expect(expired, isEmpty);

        grace.start(() => expired.add('fresh'));
        async.elapse(reconnectGrace);
        expect(expired, ['fresh']);
      });
    });

    test('a start after it ran begins a new grace', () {
      fakeAsync((async) {
        final grace = DisconnectGrace();
        var expired = 0;

        grace.start(() => expired++);
        async.elapse(reconnectGrace);
        grace.start(() => expired++);
        async.elapse(reconnectGrace);

        expect(expired, 2);
      });
    });
  });
}
