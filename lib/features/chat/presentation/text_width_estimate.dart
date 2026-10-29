import 'package:flutter/material.dart';

const _remembered = 200;
final _widths = <(String, TextStyle, TextDirection, TextScaler), double>{};

double estimateTextWidth(
  BuildContext context,
  String text, {
  double padding = 24,
}) {
  final key = (
    text,
    DefaultTextStyle.of(context).style,
    Directionality.of(context),
    MediaQuery.textScalerOf(context),
  );
  final width = _widths.remove(key) ?? _measure(key);
  _widths[key] = width;
  if (_widths.length > _remembered) _widths.remove(_widths.keys.first);
  return width + padding;
}

double _measure((String, TextStyle, TextDirection, TextScaler) key) {
  final (text, style, direction, scaler) = key;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
    textScaler: scaler,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}
