import 'package:flutter/widgets.dart';

class BottomBars extends StatelessWidget {
  final double maxHeight;
  final Widget child;

  const BottomBars({required this.maxHeight, required this.child, super.key});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: maxHeight),
    child: SingleChildScrollView(primary: false, reverse: true, child: child),
  );
}
