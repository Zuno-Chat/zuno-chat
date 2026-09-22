import 'package:flutter/widgets.dart';

const _zoomHeadroom = 1.5;

int previewDecodeWidth(BuildContext context) =>
    (MediaQuery.sizeOf(context).width *
            MediaQuery.devicePixelRatioOf(context) *
            _zoomHeadroom)
        .round();
