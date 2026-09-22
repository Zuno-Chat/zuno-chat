import 'package:flutter/widgets.dart';

bool isRoomForeground(AppLifecycleState state) =>
    state == AppLifecycleState.resumed;
