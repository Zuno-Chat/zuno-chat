import 'dart:io';

enum AppPlatform { android, ios }

final AppPlatform currentAppPlatform = Platform.isIOS
    ? AppPlatform.ios
    : AppPlatform.android;
