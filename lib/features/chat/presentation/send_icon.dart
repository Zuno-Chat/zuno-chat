import 'package:flutter/material.dart';

class SendIcon extends StatelessWidget {
  const SendIcon({super.key});

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: const Offset(2, 0),
    child: const Icon(Icons.send_rounded),
  );
}
