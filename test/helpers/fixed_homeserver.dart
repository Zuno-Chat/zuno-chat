import 'dart:async';

import 'package:zuno/core/matrix/homeserver.dart';

class FixedHomeserver extends HomeserverNotifier {
  final FutureOr<Uri> _homeserver;

  FixedHomeserver(this._homeserver);

  @override
  FutureOr<Uri> build() => _homeserver;
}
