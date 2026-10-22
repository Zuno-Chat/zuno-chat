import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder switchTile(String title) =>
    find.widgetWithText(SwitchListTile, title, skipOffstage: false);

bool switchedOn(WidgetTester tester, String title) =>
    tester.widget<SwitchListTile>(switchTile(title)).value;
