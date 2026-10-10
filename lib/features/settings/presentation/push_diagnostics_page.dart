import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/notifications/notification_delivery_mode.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/push/push_diagnostics_data.dart' show ServerReach;
import '../../../core/push/push_diagnostics_report.dart';
import '../../../core/push/push_diagnostics_source.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
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
          ? _couldNotCheck
          : buildPushDiagnostics(inputs);
    });
  }

  Future<void> _sendTest() async {
    setState(() => _testing = true);
    final outcome = await ref.read(pushDiagnosticsSourceProvider).sendTest();
    if (!mounted) return;
    setState(() => _testing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (outcome) {
          PushTestOutcome.sent =>
            'Test notification sent. If nothing arrives within a minute, '
                'notifications are not reaching this device.',
          PushTestOutcome.rateLimited =>
            'Too many tests in the last hour. Try again later.',
          PushTestOutcome.notAvailable =>
            'Test notifications are not available on this server.',
          PushTestOutcome.failed =>
            'Test not sent. Check your connection and try again.',
        }),
      ),
    );
  }

  Future<void> _share() async {
    final inputs = _inputs;
    final sections = _sections;
    if (inputs == null || sections == null) return;
    final text = redactedDiagnosticsText(
      sections,
      now: inputs.now,
      appVersion: inputs.appVersion,
    );
    await (widget.share ?? _shareText)(text);
  }

  @override
  Widget build(BuildContext context) {
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
      testSubtitle = 'It shows even while Zuno is open';
    } else if (backgroundSync) {
      testSubtitle = 'Not available with background sync';
    } else {
      testSubtitle = 'Not available on this server';
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CardListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (sections == null)
              const CardGroup(children: [ListTile(title: Text('Loading…'))])
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
                  title: const Text('Send a test notification'),
                  subtitle: Text(testSubtitle),
                  enabled: testAvailable && !_testing,
                  onTap: _sendTest,
                ),
                ListTile(
                  leading: const Icon(Icons.ios_share_outlined),
                  title: const Text('Share diagnostics'),
                  subtitle: const Text(
                    'Leaves out names, addresses and message content',
                  ),
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
                    title: const Text('Recent pushes'),
                    subtitle: const Text(
                      'When notifications arrived and what happened',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RecentPushesPage(),
                      ),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.troubleshoot_outlined),
                  title: const Text('Push target'),
                  subtitle: const Text('How notifications reach this device'),
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

const _couldNotCheck = [
  DiagnosticSection('Status', [
    DiagnosticRow(
      'Diagnostics',
      'Could not check. Pull down to try again.',
      DiagnosticStatus.warning,
    ),
  ]),
];

Future<void> _shareText(String text) async {
  await SharePlus.instance.share(
    ShareParams(text: text, subject: 'Zuno notification diagnostics'),
  );
}

class _DiagnosticTile extends StatelessWidget {
  const _DiagnosticTile(this.row);

  final DiagnosticRow row;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, color) = switch (row.status) {
      DiagnosticStatus.ok => (Icons.check_circle_outline, colors.primary),
      DiagnosticStatus.warning => (
        Icons.warning_amber_outlined,
        colors.tertiary,
      ),
      DiagnosticStatus.problem => (Icons.error_outline, colors.error),
      DiagnosticStatus.info => (Icons.info_outline, colors.onSurfaceVariant),
    };
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(row.label),
      subtitle: SelectableText(row.value),
    );
  }
}
