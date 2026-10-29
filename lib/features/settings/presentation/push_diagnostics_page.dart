import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/format/date_labels.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/push/delivery/notification_delivery_mode.dart';
import '../../../core/push/diagnostics/push_diagnostics_data.dart'
    show ServerReach;
import '../../../core/push/diagnostics/push_diagnostics_report.dart';
import '../../../core/push/diagnostics/push_diagnostics_source.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import '../../../core/ui/notice.dart';
import '../../../core/ui/status_icon.dart';
import 'push_target_status_page.dart';
import 'recent_pushes_page.dart';

class PushDiagnosticsPage extends ConsumerStatefulWidget {
  const PushDiagnosticsPage({super.key, this.share});

  final Future<void> Function(String text)? share;

  @override
  ConsumerState<PushDiagnosticsPage> createState() =>
      _PushDiagnosticsPageState();
}

class _PushDiagnosticsPageState extends ConsumerState<PushDiagnosticsPage> {
  PushDiagnosticsInputs? _inputs;
  List<DiagnosticSection>? _sections;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    PushDiagnosticsInputs? inputs;
    try {
      inputs = await ref
          .read(pushDiagnosticsSourceProvider)
          .load(
            ref.read(platformCapabilitiesProvider),
            ref.read(notificationDeliveryModeProvider),
          );
    } catch (e, s) {
      reportCaught('read push diagnostics', e, s);
    }
    if (!mounted) return;
    setState(() {
      _inputs = inputs;
      _sections = inputs == null
          ? _couldNotCheck(context.l10n)
          : buildPushDiagnostics(inputs, DateLabels.of(context));
    });
  }

  Future<void> _sendTest() async {
    setState(() => _testing = true);
    final outcome = await ref.read(pushDiagnosticsSourceProvider).sendTest();
    if (!mounted) return;
    setState(() => _testing = false);
    final l10n = context.l10n;
    ScaffoldMessenger.of(context).say(switch (outcome) {
      PushTestOutcome.sent => l10n.diagnosticsTestSent,
      PushTestOutcome.rateLimited => l10n.diagnosticsTestRateLimited,
      PushTestOutcome.notAvailable => l10n.diagnosticsTestNotAvailable,
      PushTestOutcome.failed => l10n.diagnosticsTestFailed,
    });
  }

  Future<void> _share() async {
    final inputs = _inputs;
    if (inputs == null) return;
    final sections = buildPushDiagnostics(inputs, _englishLabels);
    final text = redactedDiagnosticsText(
      englishLocalizations,
      sections,
      now: inputs.now,
      appVersion: inputs.appVersion,
    );
    await (widget.share ?? _shareText)(text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sections = _sections;
    final mode = ref.watch(notificationDeliveryModeProvider);
    final backgroundSync = mode == NotificationDeliveryMode.backgroundService;
    final testAvailable =
        !backgroundSync &&
        switch (_inputs?.reach) {
          ServerReach.notInstalled || ServerReach.turnedOff => false,
          _ => true,
        };
    final String testSubtitle;
    if (testAvailable) {
      testSubtitle = l10n.diagnosticsTestShowsWhileOpen;
    } else if (backgroundSync) {
      testSubtitle = l10n.diagnosticsTestNotWithBackgroundSync;
    } else {
      testSubtitle = l10n.diagnosticsTestNotOnServer;
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.diagnosticsTitle)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CardListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (sections == null)
              CardGroup(children: [ListTile(title: Text(l10n.commonLoading))])
            else
              for (final section in sections)
                CardGroup(
                  title: section.title,
                  children: [
                    for (final row in section.rows) _DiagnosticTile(row),
                  ],
                ),
            CardGroup(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: Text(l10n.diagnosticsSendTest),
                  subtitle: Text(testSubtitle),
                  enabled: testAvailable && !_testing,
                  onTap: _sendTest,
                ),
                ListTile(
                  leading: const Icon(Icons.ios_share_outlined),
                  title: Text(l10n.diagnosticsShare),
                  subtitle: Text(l10n.diagnosticsShareHint),
                  enabled: _inputs != null,
                  onTap: _share,
                ),
              ],
            ),
            CardGroup(
              children: [
                if (deliveryLogsEachPush(mode))
                  ListTile(
                    leading: const Icon(Icons.history_outlined),
                    title: Text(l10n.pushRecentTitle),
                    subtitle: Text(l10n.diagnosticsRecentPushesHint),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RecentPushesPage(),
                      ),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.troubleshoot_outlined),
                  title: Text(l10n.pushTargetTitle),
                  subtitle: Text(l10n.diagnosticsPushTargetHint),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PushTargetStatusPage(),
                      ),
                    );
                    if (mounted) await _load();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

List<DiagnosticSection> _couldNotCheck(AppLocalizations l10n) => [
  DiagnosticSection(l10n.diagnosticsSectionStatus, [
    DiagnosticRow(
      l10n.diagnosticsTitle,
      l10n.diagnosticsCouldNotCheckPullDown,
      DiagnosticStatus.warning,
    ),
  ]),
];

final _englishLabels = DateLabels(
  englishLocalizations,
  locale: englishLocalizations.localeName,
  use24Hour: false,
);

Future<void> _shareText(String text) async {
  await SharePlus.instance.share(
    ShareParams(
      text: text,
      subject: englishLocalizations.diagnosticsReportTitle,
    ),
  );
}

class _DiagnosticTile extends StatelessWidget {
  const _DiagnosticTile(this.row);

  final DiagnosticRow row;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: StatusIcon(row.status),
      title: Text(row.label),
      subtitle: SelectableText(row.value),
    );
  }
}
