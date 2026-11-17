import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../network/app_http_client.dart';
import '../platform/platform_capabilities.dart';
import 'update_checks.dart';
import 'update_source.dart';

Future<AvailableUpdate?> findUpdate({
  required String? installerStore,
  required int installedBuild,
  required String packageName,
  required Set<UpdateSource> offered,
  required http.Client client,
  required Future<int?> Function() play,
  required String osVersion,
}) async {
  AvailableUpdate? offer;
  switch (updateSourceFor(installerStore, offered)) {
    case UpdateSource.play:
      offer = checkPlay(await play(), packageName: packageName);
    case UpdateSource.appStore:
      offer = await checkAppStore(
        client,
        bundleId: packageName,
        osVersion: osVersion,
      );
    case UpdateSource.website:
      offer = await checkWebsite(client);
    case null:
  }
  return offer != null && offer.build > installedBuild ? offer : null;
}

const _appUpdateChannel = MethodChannel('zuno/app_update');

final updateFinderProvider = Provider<Future<AvailableUpdate?> Function()>(
  (ref) => () async {
    final info = await PackageInfo.fromPlatform();
    final installedBuild = int.tryParse(info.buildNumber);
    if (installedBuild == null) return null;
    final client = appHttpClient(HttpClientKind.service);
    try {
      return await findUpdate(
        installerStore: info.installerStore,
        installedBuild: installedBuild,
        packageName: info.packageName,
        offered: ref.read(platformCapabilitiesProvider).updateSources,
        client: client,
        play: () => _appUpdateChannel.invokeMethod<int>('playUpdate'),
        osVersion: ref.read(operatingSystemVersionProvider),
      );
    } finally {
      client.close();
    }
  },
);
