import 'package:flutter/services.dart';

bool isKeychainUnavailable(PlatformException error) => error.code == 'keychain';
