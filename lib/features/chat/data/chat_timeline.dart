import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

class ChatTimeline extends ChangeNotifier
    implements ValueListenable<Timeline?> {
  Timeline? _value;

  @override
  Timeline? get value => _value;

  set value(Timeline? timeline) {
    if (identical(_value, timeline)) return;
    _value = timeline;
    notifyListeners();
  }

  void changed() => notifyListeners();
}
