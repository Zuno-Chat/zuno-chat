import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/settings/app_preferences_provider.dart';

class CrashReportsTile extends ConsumerWidget {
  const CrashReportsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return SwitchListTile(
      secondary: const Icon(Icons.bug_report_outlined),
      title: Text(l10n.settingsAboutCrashReports),
      subtitle: Text(l10n.settingsAboutCrashReportsSubtitle),
      value: ref.watch(crashReportingProvider),
      onChanged: (value) =>
          ref.read(crashReportingProvider.notifier).set(value),
    );
  }
}
