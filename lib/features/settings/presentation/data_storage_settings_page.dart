import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/map_tile_cache.dart';
import '../../../core/matrix/attachment_cache.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';

class DataStorageSettingsPage extends ConsumerWidget {
  const DataStorageSettingsPage({super.key});

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear cache?'),
        content: const Text(
          'Clears the messages and room details saved on this device, then '
          'downloads them again. Nothing is deleted on the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear cache'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(matrixClientProvider).clearCache();
    messenger.showSnackBar(const SnackBar(content: Text('Cache cleared')));
  }

  Future<void> _clearMediaCache(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    AttachmentCache.instance.clear();
    await DiskAttachmentCache.instance.clear();
    await purgeMapTileCache();
    PaintingBinding.instance.imageCache.clear();
    messenger.showSnackBar(
      const SnackBar(content: Text('Media cache cleared')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduceMediaSize = ref.watch(reduceMediaSizeProvider);
    final lowDataCalls = ref.watch(lowDataCallsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Data & storage')),
      body: CardListView(
        children: [
          CardGroup(
            title: 'Data use',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.photo_size_select_large_outlined),
                title: const Text('Reduce media size'),
                subtitle: const Text(
                  'Compresses photos and videos more before sending. Smaller '
                  'and faster, with a bigger loss in quality. Off still '
                  'compresses, just less.',
                ),
                value: reduceMediaSize,
                onChanged: (value) =>
                    ref.read(reduceMediaSizeProvider.notifier).set(value),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.data_saver_on_outlined),
                title: const Text('Use less data for calls'),
                subtitle: Text(
                  lowDataCalls
                      ? 'Video is capped at 360p and 24 fps'
                      : 'Video is capped at 480p and 30 fps. Turn on to drop '
                            'to 360p and 24 fps.',
                ),
                value: lowDataCalls,
                onChanged: (value) =>
                    ref.read(lowDataCallsProvider.notifier).set(value),
              ),
            ],
          ),
          CardGroup(
            title: 'Storage',
            children: [
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('Clear cache'),
                subtitle: const Text(
                  'Messages and room details saved on this device. They '
                  'download again.',
                ),
                onTap: () => _clearCache(context, ref),
              ),
              ListTile(
                leading: const Icon(Icons.image_not_supported_outlined),
                title: const Text('Clear media cache'),
                subtitle: const Text(
                  'Images and photos saved on this device for up to a day',
                ),
                onTap: () => _clearMediaCache(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
