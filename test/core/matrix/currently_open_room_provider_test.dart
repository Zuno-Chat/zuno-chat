import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/currently_open_room_provider.dart';

void main() {
  test('starts as null', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(currentlyOpenRoomIdProvider), isNull);
  });

  test('set() updates the value, including back to null', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(currentlyOpenRoomIdProvider.notifier).set('!room:x');
    expect(container.read(currentlyOpenRoomIdProvider), '!room:x');
    container.read(currentlyOpenRoomIdProvider.notifier).set(null);
    expect(container.read(currentlyOpenRoomIdProvider), isNull);
  });

  test('current getter mirrors the provider\'s own state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(currentlyOpenRoomIdProvider.notifier);
    notifier.set('!room:x');
    expect(notifier.current, '!room:x');
  });
}
