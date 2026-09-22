import 'package:matrix/matrix.dart';

bool isReadByOthers(Room room, Event event) {
  final ts = event.originServerTs.millisecondsSinceEpoch;
  return room.receiptState.global.otherUsers.values.any(
    (receipt) => receipt.ts >= ts,
  );
}

List<({User user, DateTime at})> seenByOthers(Room room, Event event) {
  final ts = event.originServerTs.millisecondsSinceEpoch;
  return room.receiptState.global.otherUsers.entries
      .where((entry) => entry.value.ts >= ts)
      .map(
        (entry) => (
          user: room.unsafeGetUserFromMemoryOrFallback(entry.key),
          at: entry.value.timestamp,
        ),
      )
      .toList()
    ..sort((a, b) => a.at.compareTo(b.at));
}
