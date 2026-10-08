import 'dart:async';

import 'package:flutter/foundation.dart';

import 'current_position.dart';

class OwnLocationTracker extends ChangeNotifier {
  OwnLocationTracker({Stream<LocationFix> Function()? watch})
    : _watch = watch ?? watchOwnLocation;

  final Stream<LocationFix> Function() _watch;
  final _failures = StreamController<LocationFailure>.broadcast();
  StreamSubscription<LocationFix>? _updates;
  var _showing = false;
  var _active = false;
  LocationFound? _fix;

  bool get showing => _showing;

  LocationFound? get fix => _fix;

  Stream<LocationFailure> get failures => _failures.stream;

  set active(bool active) {
    if (_active == active) return;
    _active = active;
    _follow();
  }

  void toggle() => _showing ? hide() : show();

  void show() {
    if (_showing) return;
    _showing = true;
    _follow();
    notifyListeners();
  }

  void hide() {
    if (!_showing) return;
    _showing = false;
    _fix = null;
    _follow();
    notifyListeners();
  }

  void _follow() {
    final run = _showing && _active;
    if (run && _updates == null) {
      _updates = _watch().listen(_onFix);
    } else if (!run && _updates != null) {
      unawaited(_updates!.cancel());
      _updates = null;
    }
  }

  void _onFix(LocationFix fix) {
    switch (fix) {
      case LocationFound():
        _fix = fix;
        notifyListeners();
      case LocationFailed(:final reason):
        hide();
        _failures.add(reason);
    }
  }

  @override
  void dispose() {
    unawaited(_updates?.cancel());
    unawaited(_failures.close());
    super.dispose();
  }
}
