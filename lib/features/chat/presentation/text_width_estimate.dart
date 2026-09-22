import 'package:flutter/material.dart';

double estimateTextWidth(
  BuildContext context,
  String text, {
  double padding = 24,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: DefaultTextStyle.of(context).style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  return painter.width + padding;
}
