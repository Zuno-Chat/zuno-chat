import 'package:flutter/widgets.dart';

const _zoomHeadroom = 1.5;

int decodeWidth(BuildContext context, {double? shownAt}) =>
    ((shownAt ?? MediaQuery.sizeOf(context).width) *
            MediaQuery.devicePixelRatioOf(context))
        .round();

int previewDecodeWidth(BuildContext context) =>
    (decodeWidth(context) * _zoomHeadroom).round();
