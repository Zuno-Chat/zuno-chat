import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/platform/platform_capabilities.dart';
import '../../../core/push/push_diagnostics_report.dart';
import '../../../core/push/push_diagnostics_source.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';

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
          .load(ref.read(platformCapabilitiesProvider));
    } catch (e) {
      debugPrint('zuno/push: diagnostics could not be read ($e)');
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
                  subtitle: const Text('It shows even while Zuno is open'),
                  enabled: !_testing,
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
