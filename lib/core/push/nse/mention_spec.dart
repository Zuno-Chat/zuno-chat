import 'package:matrix/matrix.dart';

const suppressNoticesRule = '.m.rule.suppress_notices';
const mentionRuleIds = [
  '.m.rule.is_user_mention',
  '.m.rule.contains_display_name',
  '.m.rule.is_room_mention',
  '.m.rule.roomnotif',
];
const _anyMember = '@zuno.any.member:invalid';

Map<String, Object?> mentionSpecOf(
  PushRuleSet? rules, {
  required String mxid,
  required String? displayName,
}) {
  final overrides = rules?.override ?? const <PushRule>[];
  bool enabled(String id) =>
      rules == null ||
      overrides.any((rule) => rule.ruleId == id && rule.enabled);
  final content = rules?.content;
  return {
    'mxid': mxid,
    'display_name': displayName,
    'keywords': [
      if (content == null)
        {'pattern': mxid.localpart ?? '', 'highlight': true}
      else
        for (final rule in content)
          if (rule.enabled && (rule.pattern?.isNotEmpty ?? false))
            {
              'pattern': rule.pattern,
              'highlight': EvaluatedPushRuleAction.fromActions(rule.actions)
                  .highlight,
            },
    ],
    'rules': {
      for (final id in [suppressNoticesRule, ...mentionRuleIds])
        id: enabled(id),
    },
  };
}

List<String> roomNotifiers(Room room) {
  if (room.canSendNotification(_anyMember)) return const ['*'];
  final listed =
      room
          .getState(EventTypes.RoomPowerLevels)
          ?.content
          .tryGetMap<String, Object?>('users')
          ?.keys ??
      const <String>[];
  return {
    ...room.creatorUserIds,
    ...listed,
  }.where(room.canSendNotification).toList()..sort();
}
