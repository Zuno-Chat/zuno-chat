import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/format/chat_list_time.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/push/push_diagnostics_source.dart';
import '../../../core/push/recent_pushes.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';

class RecentPushesPage extends ConsumerStatefulWidget {
  const RecentPushesPage({super.key});

  @override
  ConsumerState<RecentPushesPage> createState() => _RecentPushesPageState();
}

class _RecentPushesPageState extends ConsumerState<RecentPushesPage> {
  List<RecentPush>? _pushes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var pushes = const <RecentPush>[];
    try {
      pushes = await ref
          .read(pushDiagnosticsSourceProvider)
          .recentPushes(
            ref.read(platformCapabilitiesProvider),
            ref.read(notificationDeliveryModeProvider),
          );
    } catch (e, s) {
      reportCaught('read recent pushes', e, s);
    }
    if (!mounted) return;
    setState(() => _pushes = pushes);
  }

  @override
  Widget build(BuildContext context) {
    final pushes = _pushes;
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Recent pushes')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CardListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            CardGroup(
              children: [
                if (pushes == null)
                  const ListTile(title: Text('Loading…'))
                else if (pushes.isEmpty)
                  const ListTile(title: Text('None yet'))
                else
                  for (final push in pushes.take(shownRecentPushes))
                    ListTile(
                      leading: push.late
                          ? Icon(Icons.schedule_outlined, color: colors.error)
                          : const Icon(Icons.check_circle_outline),
                      title: Text(_receivedLabel(push.at, use24Hour)),
                      subtitle: Text(push.summary),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _receivedLabel(DateTime at, bool use24Hour) {
  final day = chatListTimeLabel(at, now: DateTime.now(), use24Hour: use24Hour);
  final clock = clockLabel(at.toLocal(), use24Hour);
  return day == clock ? clock : '$day, $clock';
}
