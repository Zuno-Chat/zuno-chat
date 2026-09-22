import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/features/chat/presentation/room_lifecycle.dart';

void main() {
  test('resumed counts as foreground', () {
    expect(isRoomForeground(AppLifecycleState.resumed), isTrue);
  });

  test('paused, inactive, hidden and detached do not count as foreground', () {
    for (final state in [
      AppLifecycleState.paused,
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
    ]) {
      expect(isRoomForeground(state), isFalse, reason: state.toString());
    }
  });
}
