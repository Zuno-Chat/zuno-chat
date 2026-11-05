import 'package:flutter/material.dart';
import 'package:zuno/core/navigation/chat_route.dart';

Widget routeLauncher<T>(
  WidgetBuilder page, {
  String label = 'open',
  String? chat,
  ValueChanged<T?>? onResult,
}) => Builder(
  builder: (context) {
    if (chat != null) markChatRoute(context, chat);
    return TextButton(
      onPressed: () async {
        final result = await Navigator.of(context)
            .push(MaterialPageRoute<T>(builder: page));
        onResult?.call(result);
      },
      child: Text(label),
    );
  },
);
