import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/navigation/held_broadcast.dart';

void main() {
  late HeldBroadcast<String> broadcast;

  setUp(() => broadcast = HeldBroadcast<String>());

  Future<List<String>> listenBriefly() async {
    final heard = <String>[];
    final sub = broadcast.stream.listen(heard.add);
    await pumpEventQueue();
    await sub.cancel();
    return heard;
  }

  test('an event added while someone listens goes to them and is not '
      'kept', () async {
    final heard = <String>[];
    final sub = broadcast.stream.listen(heard.add);
    broadcast.add('now');
    await pumpEventQueue();
    await sub.cancel();

    expect(heard, ['now']);
    expect(await listenBriefly(), isEmpty);
  });

  test('an event added before anyone listens reaches the first listener, '
      'once', () async {
    broadcast.add('early');

    final first = <String>[];
    final second = <String>[];
    final firstSub = broadcast.stream.listen(first.add);
    final secondSub = broadcast.stream.listen(second.add);
    await pumpEventQueue();
    await firstSub.cancel();
    await secondSub.cancel();

    expect(first, ['early']);
    expect(second, isEmpty);
    expect(await listenBriefly(), isEmpty);
  });

  test('of several unheard events, only the latest is kept', () async {
    broadcast
      ..add('older')
      ..add('newer');

    expect(await listenBriefly(), ['newer']);
    expect(await listenBriefly(), isEmpty);
  });
}
