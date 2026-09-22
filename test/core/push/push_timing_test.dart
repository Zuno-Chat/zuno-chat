import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/push_timing.dart';

void main() {
  test('reports each step as its own duration plus the total', () {
    var now = 0;
    final timing = PushTiming('fcm', elapsedMs: () => now);

    now = 800;
    timing.mark('client');
    now = 2200;
    timing.mark('fetch');
    now = 2250;
    timing.mark('post');

    expect(
      timing.report(),
      'zuno/push: timing fcm client=800ms fetch=1400ms post=50ms total=2250ms',
    );
  });

  test('a timing with no marks reports only the total', () {
    var now = 0;
    final timing = PushTiming('unifiedpush', elapsedMs: () => now);
    now = 12;

    expect(timing.report(), 'zuno/push: timing unifiedpush total=12ms');
  });
}
