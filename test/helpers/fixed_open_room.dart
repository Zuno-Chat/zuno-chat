import 'package:flutter_riverpod/misc.dart';
import 'package:zuno/core/matrix/currently_open_room_provider.dart';

class FixedOpenRoomNotifier extends CurrentlyOpenRoomIdNotifier {
  FixedOpenRoomNotifier(this._roomId);
  final String? _roomId;

  @override
  String? build() => _roomId;

  void open(String? roomId) => state = roomId;
}

Override fixedOpenRoom(String? roomId) => currentlyOpenRoomIdProvider
    .overrideWith(() => FixedOpenRoomNotifier(roomId));
