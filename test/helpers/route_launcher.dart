import 'package:flutter/material.dart';

Widget routeLauncher<T>(
  WidgetBuilder page, {
  String label = 'open',
  ValueChanged<T?>? onResult,
}) => Builder(
  builder: (context) => TextButton(
    onPressed: () async {
      final result = await Navigator.of(context)
          .push(MaterialPageRoute<T>(builder: page));
      onResult?.call(result);
    },
    child: Text(label),
  ),
);
