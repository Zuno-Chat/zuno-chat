import 'package:flutter/widgets.dart';

StrutStyle lineStrut(TextStyle style) =>
    StrutStyle.fromTextStyle(style, forceStrutHeight: true);

StrutStyle inheritedLineStrut(BuildContext context) =>
    lineStrut(DefaultTextStyle.of(context).style);
