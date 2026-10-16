import 'dart:convert';

import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../calls/matrixrtc/call_unread_correction_provider.dart';
import '../../errors/caught_errors.dart';
import '../../notifications/messages/notified_events_store.dart';
import '../../notifications/settings/notification_preview.dart';
import '../../notifications/settings/notify_me.dart';
import 'mention_spec.dart';
import 'nse_app_channel.dart';
import 'opaque_thread_ids.dart';

class NseOutcomeSummary {
  const NseOutcomeSummary({
    required this.authFailed,
    required this.generationChanged,
  });

  final bool authFailed;
  final bool generationChanged;
}

class NseOutcomeReader {
  NseOutcomeReader({required this.channel, required this.prefs});

  static const countersKey = 'nse.counters';
  static const generationKey = 'nse.generation';

  final NseAppChannel channel;
  final SharedPreferences prefs;

  Future<NseOutcomeSummary> read() async {
    for (final mark in await channel.takeMarks()) {
      final room = mark.room;
      if (mark.kind == 'invite' && room != null) {
        await markInviteAnnouncedOnDisk(
          prefs,
          room,
          now: DateTime.fromMillisecondsSinceEpoch(mark.ts),
        );
      }
    }
    final report = await channel.readOutcomes();
    final before = _authCounts();
    final auth = {
      for (final MapEntry(:key, :value) in report.counters.entries)
        if (key.endsWith('.o.auth')) key: value,
    };
    await prefs.setString(countersKey, jsonEncode(auth));
    final generation = report.generation;
    final previous = prefs.getString(generationKey);
    final changed =
        generation != null && previous != null && generation != previous;
    if (generation != null) await prefs.setString(generationKey, generation);
    return NseOutcomeSummary(
      authFailed: auth.entries.any(
        (entry) => entry.value > (before[entry.key] ?? 0),
      ),
      generationChanged: changed,
    );
  }

  Map<String, int> _authCounts() {
    final Object? decoded;
    try {
      decoded = jsonDecode(prefs.getString(countersKey) ?? '{}');
    } on FormatException {
      return {};
    } catch (e, s) {
      reportCaught('nse outcome counters read', e, s);
      return {};
    }
    if (decoded is! Map) return {};
    return {
      for (final MapEntry(:key, :value) in decoded.entries)
        if (key is String && value is int) key: value,
    };
  }
}

List<String> badgeRoomIds(Client client, Map<String, int> corrections) => [
  for (final room in client.rooms)
    if (room.membership == Membership.invite ||
        (room.membership == Membership.join &&
            displayedUnreadCount(corrections, room) > 0))
      room.id,
];

Future<Map<String, Object?>> nseMetaFields({
  required Client client,
  required NotificationPreview preview,
  required NotifyMe notifyMe,
  required bool messageTone,
  required List<String> unreadRoomIds,
  required OpaqueThreadIds threadIds,
  required String? displayName,
  required Set<String> askedToJoin,
}) async => {
  'base_url': client.homeserver?.toString(),
  'level': preview.wire,
  'notify': notifyMe == NotifyMe.mentionsOnly ? 'mentions' : 'all',
  'tone': messageTone,
  'unread': await threadIds.tokensFor(unreadRoomIds),
  'mention': mentionSpecOf(
    client.globalPushRules,
    mxid: client.userID ?? '',
    displayName: displayName,
  ),
  'asked': [...askedToJoin]..sort(),
};
