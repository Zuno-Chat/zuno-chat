import 'package:matrix/matrix.dart';

class ReactionSummary {
  final String key;
  final int count;
  final bool reactedByMe;

  const ReactionSummary({
    required this.key,
    required this.count,
    required this.reactedByMe,
  });
}

String? _reactionKey(Event reaction) => reaction.content
    .tryGetMap<String, Object?>('m.relates_to')
    ?.tryGet<String>('key');

List<ReactionSummary> reactionSummaries(Event event, Timeline timeline) {
  final myUserId = event.room.client.userID;
  final counts = <String, int>{};
  final mine = <String>{};

  for (final reaction in event.aggregatedEvents(
    timeline,
    RelationshipTypes.reaction,
  )) {
    if (reaction.redacted) continue;
    final key = _reactionKey(reaction);
    if (key == null) continue;
    counts[key] = (counts[key] ?? 0) + 1;
    if (reaction.senderId == myUserId) mine.add(key);
  }

  return [
    for (final entry in counts.entries)
      ReactionSummary(
        key: entry.key,
        count: entry.value,
        reactedByMe: mine.contains(entry.key),
      ),
  ];
}

Future<void> toggleReaction(Event event, Timeline timeline, String key) async {
  final room = event.room;
  final myUserId = room.client.userID;

  Event? myExisting;
  for (final reaction in event.aggregatedEvents(
    timeline,
    RelationshipTypes.reaction,
  )) {
    if (reaction.redacted || reaction.senderId != myUserId) continue;
    myExisting = reaction;
    break;
  }

  if (myExisting != null) {
    await room.redactEvent(myExisting.eventId);
    if (_reactionKey(myExisting) == key) return;
  }
  await room.sendReaction(event.eventId, key);
}
