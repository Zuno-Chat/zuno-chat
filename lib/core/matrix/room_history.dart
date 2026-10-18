import 'package:matrix/matrix.dart';

StateEvent newRoomHistoryState() => StateEvent(
  type: EventTypes.HistoryVisibility,
  content: {'history_visibility': HistoryVisibility.invited.text},
);

HistoryVisibility historyVisibilityOf(Room room) =>
    room.historyVisibility ?? HistoryVisibility.shared;

List<HistoryVisibility> historyChoices(Room room) {
  if (!room.encrypted) return HistoryVisibility.values;
  final current = historyVisibilityOf(room);
  return [
    for (final visibility in HistoryVisibility.values)
      if (_readableWhenEncrypted.contains(visibility) || visibility == current)
        visibility,
  ];
}

const _readableWhenEncrypted = {
  HistoryVisibility.invited,
  HistoryVisibility.joined,
};
