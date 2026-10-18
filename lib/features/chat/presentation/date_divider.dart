import 'package:flutter/material.dart';

import '../../../core/ui/timeline_pill.dart';

class DateDivider extends StatelessWidget {
  final String label;

  const DateDivider({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Center(child: TimelinePill(label)),
    );
  }
}
