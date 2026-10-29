import 'package:flutter/material.dart';

import '../l10n/display_text.dart';
import 'circle_icon.dart';

class DangerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const DangerTile({
    required this.icon,
    @displayText required this.label,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    leading: CircleIcon(icon, danger: true),
    title: Text(label),
    textColor: Theme.of(context).colorScheme.error,
    onTap: onTap,
  );
}
