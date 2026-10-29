import 'package:flutter/material.dart';

import '../push/diagnostics/push_diagnostics_report.dart' show DiagnosticStatus;

class StatusIcon extends StatelessWidget {
  final DiagnosticStatus status;

  const StatusIcon(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, color) = switch (status) {
      DiagnosticStatus.ok => (Icons.check_circle_outline, colors.primary),
      DiagnosticStatus.warning => (
        Icons.warning_amber_outlined,
        colors.tertiary,
      ),
      DiagnosticStatus.problem => (Icons.error_outline, colors.error),
      DiagnosticStatus.info => (Icons.info_outline, colors.onSurfaceVariant),
    };
    return Icon(icon, color: color);
  }
}
