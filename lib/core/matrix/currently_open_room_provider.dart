import 'package:flutter_riverpod/flutter_riverpod.dart';

final currentlyOpenRoomIdProvider =
    NotifierProvider<CurrentlyOpenRoomIdNotifier, String?>(
      CurrentlyOpenRoomIdNotifier.new,
    );

class CurrentlyOpenRoomIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  String? get current => state;

  void set(String? roomId) => state = roomId;
}
