import 'package:flutter/widgets.dart';

void closeKeyboard() => FocusManager.instance.primaryFocus?.unfocus();
