import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/media/call_key_slots.dart';

void main() {
  test('gens cycle through slots 0 to 255 of a 256-slot ring, as Element '
      'numbers them', () {
    expect(keyRingSize, 256);
    expect(
      [for (var gen = 1; gen <= 257; gen++) senderKeySlot(gen)],
      [for (var slot = 0; slot <= 255; slot++) slot, 0],
    );
  });
}
