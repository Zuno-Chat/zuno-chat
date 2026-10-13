import 'package:flutter/widgets.dart';

final _rooms = Expando<String>('chat route room');

void markChatRoute(BuildContext context, String roomId) {
  final route = ModalRoute.of(context);
  if (route != null) _rooms[route] = roomId;
}

bool isChatRoute(Route<Object?>? route, String roomId) =>
    route != null && _rooms[route] == roomId;
