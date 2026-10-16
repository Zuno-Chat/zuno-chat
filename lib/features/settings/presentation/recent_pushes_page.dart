import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/format/date_labels.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/push/diagnostics/push_diagnostics_source.dart';
import '../../../core/push/diagnostics/recent_pushes.dart';
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
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    var pushes = const <RecentPush>[];
    try {
      pushes = await ref
          .read(pushDiagnosticsSourceProvider)
          .recentPushes(
            context.l10n,
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
    final l10n = context.l10n;
    final pushes = _pushes;
    final labels = DateLabels.of(context);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.pushRecentTitle)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CardListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            CardGroup(
              children: [
                if (pushes == null)
                  ListTile(title: Text(l10n.commonLoading))
                else if (pushes.isEmpty)
                  ListTile(title: Text(l10n.pushNoneYet))
                else
                  for (final push in pushes.take(shownRecentPushes))
                    ListTile(
                      leading: push.late
                          ? Icon(Icons.schedule_outlined, color: colors.error)
                          : const Icon(Icons.check_circle_outline),
                      title: Text(_receivedLabel(push.at, labels)),
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

String _receivedLabel(DateTime at, DateLabels labels) {
  final day = labels.chatList(at, now: DateTime.now());
  final clock = labels.clock(at);
  return day == clock ? clock : labels.l10n.pushReceivedDayTime(day, clock);
}
