import 'package:flutter/material.dart';

class ForwardIcon extends StatelessWidget {
  final double? size;
  final Color? color;

  const ForwardIcon({this.size, this.color, super.key});

  @override
  Widget build(BuildContext context) => Transform.flip(
    flipX: true,
    child: Icon(Icons.reply_outlined, size: size, color: color),
  );
}
