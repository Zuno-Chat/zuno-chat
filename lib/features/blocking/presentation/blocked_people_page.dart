import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/client/matrix_client_provider.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import 'block_person.dart';

class BlockedPeoplePage extends ConsumerStatefulWidget {
  final UnblockPerson? unblock;

  const BlockedPeoplePage({this.unblock, super.key});

  @override
  ConsumerState<BlockedPeoplePage> createState() => _BlockedPeoplePageState();
}

class _BlockedPeoplePageState extends ConsumerState<BlockedPeoplePage> {
  final _unblocked = <String>{};
  bool _busy = false;
  StreamSubscription<void>? _blockedListSub;

  @override
  void initState() {
    super.initState();
    _blockedListSub = ref
        .read(matrixClientProvider)
        .onSync
        .stream
        .where(
          (sync) =>
              sync.accountData?.any(
                (event) => event.type == 'm.ignored_user_list',
              ) ??
              false,
        )
        .listen((_) {
          if (mounted) setState(_unblocked.clear);
        });
  }

  @override
  void dispose() {
    _blockedListSub?.cancel();
    super.dispose();
  }

  Future<void> _unblock(String userId) async {
    setState(() => _busy = true);
    final unblocked = await unblockPerson(
      context,
      client: ref.read(matrixClientProvider),
      userId: userId,
      name: withoutServer(userId),
      unblock: widget.unblock,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (unblocked) _unblocked.add(userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(matrixClientProvider);
    final blocked =
        client.ignoredUsers.where((id) => !_unblocked.contains(id)).toList()
          ..sort();

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.blockingPageTitle)),
      body: blocked.isEmpty
          ? Center(
              child: Text(
                context.l10n.blockingNobody,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : CardListView(
              children: [
                CardGroup(
                  children: [
                    for (final userId in blocked)
                      ListTile(
                        leading: const Icon(Icons.block_outlined),
                        title: Text(withoutServer(userId)),
                        trailing: TextButton(
                          onPressed: _busy ? null : () => _unblock(userId),
                          child: Text(context.l10n.blockingUnblock),
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}
