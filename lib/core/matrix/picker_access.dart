import 'package:flutter/services.dart';

bool isPickerAccessDenied(Object error) =>
    error is PlatformException &&
    (error.code == 'camera_access_denied' ||
        error.code == 'photo_access_denied');
