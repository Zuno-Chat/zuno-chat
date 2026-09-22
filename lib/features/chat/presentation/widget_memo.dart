import 'package:flutter/widgets.dart';

class WidgetMemo {
  final int capacity;
  final _entries = <String, Widget>{};

  WidgetMemo({required this.capacity});

  Widget obtain(String key, Widget Function() build) {
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return cached;
    }
    final widget = build();
    _entries[key] = widget;
    if (_entries.length > capacity) _entries.remove(_entries.keys.first);
    return widget;
  }
}
