import 'dart:async';

import 'package:matrix/matrix.dart';

import 'fake_matrix.dart';

class GatedTimelineFakeDatabaseApi extends StoredEventsFakeDatabaseApi {
  final gate = Completer<void>();

  @override
  Future<List<Event>> getEventList(
    Room room, {
    int start = 0,
    bool onlySending = false,
    int? limit,
  }) async {
    await gate.future;
    return super.getEventList(
      room,
      start: start,
      onlySending: onlySending,
      limit: limit,
    );
  }
}
