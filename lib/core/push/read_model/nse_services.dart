import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../calls/matrixrtc/call_unread_correction_provider.dart';
import '../../errors/best_effort.dart';
import '../../errors/caught_errors.dart';
import '../../matrix/matrix_client_provider.dart';
import '../../notifications/notification_permission_provider.dart';
import '../../notifications/notification_preview.dart';
import '../../notifications/notify_me.dart';
import '../../platform/platform_capabilities.dart';
import '../../settings/app_preferences_provider.dart';
import '../nse_credential.dart';
import '../zuno_push_api.dart';
import 'nse_app_channel.dart';
import 'nse_outcomes.dart';
import 'opaque_thread_ids.dart';
import 'read_model_publisher.dart';
import 'session_exporter.dart';

typedef NseSettings = ({
  NotificationPreview preview,
  NotifyMe notifyMe,
  bool messageTone,
  bool allowed,
});

class NseServices {
  NseServices({
    required this.client,
    required this.publisher,
    required this.channel,
    required this.prefs,
    required this.settings,
    required this.unreadRoomIds,
    required Future<ZunoPushResult<NseCredentialGrant>> Function() mint,
    SessionExporter? exporter,
    OpaqueThreadIds? threadIds,
    Future<String> Function()? appVersion,
    this._displayName,
  }) : exporter = exporter ?? SessionExporter.instance,
       threadIds = threadIds ?? OpaqueThreadIds.instance,
       _appVersion = appVersion ?? _installedVersion,
       _keeper = NseCredentialKeeper(
         mint: mint,
         channel: channel,
         prefs: prefs,
       );

  static const sessionKey = 'nse.session';
  static const buildKey = 'nse.build';
  static const format = 1;

  final Client client;
  final ReadModelPublisher publisher;
  final NseAppChannel channel;
  final SharedPreferences prefs;
  final NseSettings Function() settings;
  final List<String> Function() unreadRoomIds;
  final SessionExporter exporter;
  final OpaqueThreadIds threadIds;
  final Future<String> Function() _appVersion;
  final Future<String?> Function()? _displayName;
  final NseCredentialKeeper _keeper;
  String? _name;
  List<String>? _unread;

  bool get _exports {
    final current = settings();
    return current.allowed && current.preview != NotificationPreview.nothing;
  }

  Future<void> start() async {
    threadIds.reset();
    exporter.load(prefs);
    exporter.onDirty = () => publisher.roomsChanged(exporter.takeDirtyRooms());
    publisher
      ..metaExtras = _metaExtras
      ..roomExtras = _roomExtras
      ..titles = settings().preview != NotificationPreview.nothing;
    _name = await _fetchDisplayName();
    await _rebuildIfDue();
    await publisher.refreshMeta();
    await publisher.publishAll();
    await resumed();
  }

  void stop() {
    exporter.onDirty = null;
    publisher
      ..metaExtras = null
      ..roomExtras = null
      ..titles = true;
  }

  Future<void> settingsChanged() async {
    publisher.titles = settings().preview != NotificationPreview.nothing;
    await publisher.refreshMeta();
    await publisher.publishAll();
    await _keeper.ensure(allowed: _exports);
  }

  Future<void> synced(SyncUpdate update) async {
    publisher.roomsChanged(exporter.takeDirtyRooms());
    final rules =
        update.accountData?.any((event) => event.type == 'm.push_rules') ??
        false;
    final tokens = await threadIds.tokensFor(unreadRoomIds());
    final unreadChanged = !listEquals(tokens, _unread);
    _unread = tokens;
    if (rules || unreadChanged) await publisher.refreshMeta();
    if (rules) await publisher.publishAll();
    if (unreadChanged) await channel.syncBadge(tokens);
  }

  Future<void> resumed() async {
    final summary = await NseOutcomeReader(
      channel: channel,
      prefs: prefs,
    ).read(client);
    if (summary.generationChanged) {
      threadIds.reset();
      _unread = null;
      await prefs.remove(NseCredentialKeeper.mintedKey);
      await exporter.rebuild(client);
      await publisher.refreshMeta();
      await publisher.publishAll(force: true);
    }
    final name = await _fetchDisplayName();
    if (name != _name) {
      _name = name;
      await publisher.refreshMeta();
    }
    await _keeper.ensure(
      allowed: _exports,
      afterAuthFailure: summary.authFailed,
    );
    await _syncBadge();
  }

  Future<void> paused() async {
    publisher.roomsChanged(exporter.takeDirtyRooms());
    await publisher.flush();
    await exporter.save(prefs);
    await _syncBadge();
  }

  Future<void> _syncBadge() async {
    final tokens = await threadIds.tokensFor(unreadRoomIds());
    _unread = tokens;
    await channel.syncBadge(tokens);
  }

  Future<Map<String, Object?>> _metaExtras() {
    final current = settings();
    return nseMetaFields(
      client: client,
      preview: current.preview,
      notifyMe: current.notifyMe,
      messageTone: current.messageTone,
      unreadRoomIds: unreadRoomIds(),
      threadIds: threadIds,
      displayName: _name,
    );
  }

  Future<Map<String, Object?>> _roomExtras(Room room) =>
      exporter.roomFields(room, allowed: _exports);

  Future<void> _rebuildIfDue() async {
    final session = '${client.userID}|${client.deviceID}';
    final build = '$format|${await _appVersion()}';
    final newSession = prefs.getString(sessionKey) != session;
    if (newSession) await prefs.remove(NseCredentialKeeper.mintedKey);
    if (!newSession && prefs.getString(buildKey) == build) return;
    await exporter.rebuild(client);
    await prefs.setString(sessionKey, session);
    await prefs.setString(buildKey, build);
  }

  Future<String?> _fetchDisplayName() async {
    final injected = _displayName;
    if (injected != null) return injected();
    final userId = client.userID;
    if (userId == null) return null;
    try {
      final profile = await client.getUserProfile(
        userId,
        timeout: const Duration(seconds: 5),
      );
      return profile.displayname;
    } catch (e, s) {
      reportCaught('nse display name fetch', e, s);
      return _name;
    }
  }
}

Future<String> _installedVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  } catch (e, s) {
    reportCaught('nse installed version', e, s);
    return 'unknown';
  }
}

void _safely(String step, Future<void> Function() work) =>
    unawaited(runBestEffort(work, label: 'nse $step'));

Future<ZunoPushResult<NseCredentialGrant>> mintNseCredential(
  Client client,
) async {
  if (client.homeserver == null) {
    return const ZunoPushFailure(ZunoPushFailureKind.noSession);
  }
  final api = ZunoPushApi.forClient(client);
  try {
    return await api.mintNseCredential();
  } finally {
    api.close();
  }
}

final nseServicesProvider = Provider<void>((ref) {
  if (!ref.watch(platformCapabilitiesProvider).nseNotifications) return;
  if (ref.watch(isLoggedInProvider).value != true) return;
  final publisher = ref.watch(readModelPublisherProvider);
  if (publisher == null) return;
  final client = ref.watch(matrixClientProvider);
  final services = NseServices(
    client: client,
    publisher: publisher,
    channel: ref.watch(nseAppChannelProvider),
    prefs: ref.watch(sharedPreferencesProvider),
    settings: () => (
      preview: ref.read(notificationPreviewProvider),
      notifyMe: ref.read(notifyMeProvider),
      messageTone: ref.read(messageToneEnabledProvider),
      allowed: ref.read(notificationsAllowedProvider) ?? true,
    ),
    unreadRoomIds: () =>
        badgeRoomIds(client, ref.read(callUnreadCorrectionProvider)),
    mint: () => mintNseCredential(client),
  );
  void changed() => _safely('settings', services.settingsChanged);
  ref.listen(notificationPreviewProvider, (_, _) => changed());
  ref.listen(notifyMeProvider, (_, _) => changed());
  ref.listen(messageToneEnabledProvider, (_, _) => changed());
  ref.listen(notificationsAllowedProvider, (_, _) => changed());
  final sync = client.onSync.stream.listen(
    (update) => _safely('sync', () => services.synced(update)),
  );
  final lifecycle = AppLifecycleListener(
    onResume: () => _safely('resume', services.resumed),
    onPause: () => _safely('pause', services.paused),
  );
  ref.onDispose(() {
    unawaited(sync.cancel());
    lifecycle.dispose();
    services.stop();
  });
  _safely('start', services.start);
});
