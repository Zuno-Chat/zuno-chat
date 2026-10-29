import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/location/map_tile_cache.dart';
import '../../../core/matrix/attachment_cache.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import '../../../core/ui/confirm_dialog.dart';
import '../../../core/ui/notice.dart';

class DataStorageSettingsPage extends ConsumerWidget {
  const DataStorageSettingsPage({super.key});

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await confirm(
      context,
      title: l10n.settingsDataClearCacheTitle,
      body: l10n.settingsDataClearCacheBody,
      confirmLabel: l10n.settingsDataClearCache,
      tone: ConfirmTone.primary,
    );
    if (!confirmed || !context.mounted) return;

    await attempt(
      context,
      ref.read(matrixClientProvider).clearCache,
      label: 'clear cache',
      failed: l10n.settingsDataClearCacheFailed,
      succeeded: l10n.settingsDataCacheCleared,
    );
  }

  Future<void> _clearMediaCache(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    AttachmentCache.instance.clear();
    await DiskAttachmentCache.instance.clear();
    await purgeMapTileCache();
    PaintingBinding.instance.imageCache.clear();
    messenger.say(l10n.settingsDataMediaCacheCleared);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final reduceMediaSize = ref.watch(reduceMediaSizeProvider);
    final lowDataCalls = ref.watch(lowDataCallsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsDataTitle)),
      body: CardListView(
        children: [
          CardGroup(
            title: l10n.settingsDataUse,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.photo_size_select_large_outlined),
                title: Text(l10n.settingsDataReduceMedia),
                subtitle: Text(l10n.settingsDataReduceMediaSubtitle),
                value: reduceMediaSize,
                onChanged: (value) =>
                    ref.read(reduceMediaSizeProvider.notifier).set(value),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.data_saver_on_outlined),
                title: Text(l10n.settingsDataLowDataCalls),
                subtitle: Text(l10n.settingsDataLowDataCallsSubtitle),
                value: lowDataCalls,
                onChanged: (value) =>
                    ref.read(lowDataCallsProvider.notifier).set(value),
              ),
            ],
          ),
          CardGroup(
            title: l10n.settingsDataStorage,
            children: [
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: Text(l10n.settingsDataClearCache),
                subtitle: Text(l10n.settingsDataClearCacheSubtitle),
                onTap: () => _clearCache(context, ref),
              ),
              ListTile(
                leading: const Icon(Icons.image_not_supported_outlined),
                title: Text(l10n.settingsDataClearMediaCache),
                subtitle: Text(l10n.settingsDataClearMediaCacheSubtitle),
                onTap: () => _clearMediaCache(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
