import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/navigation/chat_route.dart';

Future<void> openChatRoute(
  WidgetTester tester,
  NavigatorState navigator,
  String roomId,
) async {
  unawaited(
    navigator.push(
      MaterialPageRoute<void>(
        builder: (context) {
          markChatRoute(context, roomId);
          return const SizedBox();
        },
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}
