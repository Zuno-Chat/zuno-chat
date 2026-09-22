import 'package:flutter/widgets.dart';

class RowMemo<T> {
  final int? capacity;
  final _entries = <String, ({T data, Widget widget})>{};

  RowMemo({this.capacity});

  Widget obtain(String id, T data, Widget Function() build) {
    final entry = _entries.remove(id);
    if (entry != null && entry.data == data) {
      _entries[id] = entry;
      return entry.widget;
    }
    final widget = build();
    _entries[id] = (data: data, widget: widget);
    final capacity = this.capacity;
    if (capacity != null && _entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
    return widget;
  }

  void retainOnly(Iterable<String> ids) {
    final keep = ids.toSet();
    _entries.removeWhere((id, _) => !keep.contains(id));
  }

  void clear() => _entries.clear();
}
