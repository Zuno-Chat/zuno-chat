import 'package:matrix/matrix.dart';

(int, int)? mediaSize(int? width, int? height) {
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }
  return (width, height);
}

extension MediaInfo on Event {
  int? get mediaWidth => infoMap.tryGet<int>('w');

  int? get mediaHeight => infoMap.tryGet<int>('h');

  Duration? get mediaDuration => switch (infoMap.tryGet<int>('duration')) {
    final ms? => Duration(milliseconds: ms),
    null => null,
  };

  int? get fileSize => infoMap.tryGet<int>('size');
}
