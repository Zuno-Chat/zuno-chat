import 'package:flutter/widgets.dart';

import '../../../core/matrix/cover_image.dart';

const _zoomHeadroom = 1.5;

int previewDecodeWidth(BuildContext context) =>
    (decodeWidth(context) * _zoomHeadroom).round();
