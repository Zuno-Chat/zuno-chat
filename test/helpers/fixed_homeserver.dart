import 'dart:async';

import 'package:zuno/core/matrix/homeserver.dart';
import 'package:zuno/core/matrix/server_choice.dart';

class FixedHomeserver extends HomeserverNotifier {
  final FutureOr<ServerChoice> _choice;

  FixedHomeserver(this._choice);

  @override
  FutureOr<ServerChoice> build() => _choice;
}
