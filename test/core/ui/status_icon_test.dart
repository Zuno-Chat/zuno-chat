import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/diagnostics/push_diagnostics_report.dart';
import 'package:zuno/core/ui/status_icon.dart';
import 'package:zuno/core/ui/zuno_theme.dart';

void main() {
  Future<Icon> iconFor(WidgetTester tester, DiagnosticStatus status) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: zunoLightTheme,
        home: Center(child: StatusIcon(status)),
      ),
    );
    return tester.widget<Icon>(find.byType(Icon));
  }

  final colors = zunoLightTheme.colorScheme;

  for (final (status, glyph, color) in [
    (DiagnosticStatus.ok, Icons.check_circle_outline, colors.primary),
    (DiagnosticStatus.warning, Icons.warning_amber_outlined, colors.tertiary),
    (DiagnosticStatus.problem, Icons.error_outline, colors.error),
    (DiagnosticStatus.info, Icons.info_outline, colors.onSurfaceVariant),
  ]) {
    testWidgets('${status.name} has its own glyph and colour', (tester) async {
      final icon = await iconFor(tester, status);

      expect(icon.icon, glyph);
      expect(icon.color, color);
    });
  }
}
