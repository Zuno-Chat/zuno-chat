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

List<ReactionSummary> reactionSummaries(
  Event event,
  Timeline timeline, {
  Iterable<Event> fetched = const [],
}) {
  final myUserId = event.room.client.userID;
  final live = event.aggregatedEvents(timeline, RelationshipTypes.reaction);
  final liveIds = {for (final reaction in live) reaction.eventId};
  final counts = <String, int>{};
  final mine = <String>{};

  for (final reaction in [
    ...live,
    ...fetched.where((reaction) => !liveIds.contains(reaction.eventId)),
  ]) {
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

Future<List<Event>> fetchReactions(Event event) async {
  final room = event.room;
  final client = room.client;
  final encryption = client.encryption;
  final reactions = <Event>[];
  String? from;
  do {
    final page = await client.getRelatingEventsWithRelType(
      room.id,
      event.eventId,
      RelationshipTypes.reaction,
      from: from,
    );
    for (final raw in page.chunk) {
      final reaction = Event.fromMatrixEvent(raw, room);
      reactions.add(
        reaction.type == EventTypes.Encrypted && encryption != null
            ? await encryption.decryptRoomEvent(reaction)
            : reaction,
      );
    }
    from = page.nextBatch;
  } while (from != null);
  return reactions;
}

Future<void> toggleReaction(Event event, Timeline timeline, String key) async {
  final room = event.room;
  final loaded = timeline.events.any((e) => e.eventId == event.eventId);
  final myExisting = loaded
      ? _myLoadedReaction(event, timeline)
      : await _myServerReaction(event);

  if (myExisting != null) {
    if (myExisting.status.isSending) return;
    if (myExisting.status.isError) {
      await myExisting.cancelSend();
    } else {
      await room.redactEvent(myExisting.eventId);
    }
    if (_reactionKey(myExisting) == key) return;
  }
  await room.sendReaction(event.eventId, key);
}

Event? _myLoadedReaction(Event event, Timeline timeline) {
  final myUserId = event.room.client.userID;
  for (final reaction in event.aggregatedEvents(
    timeline,
    RelationshipTypes.reaction,
  )) {
    if (reaction.redacted || reaction.senderId != myUserId) continue;
    return reaction;
  }
  return null;
}

Future<Event?> _myServerReaction(Event event) async {
  final myUserId = event.room.client.userID;
  for (final reaction in await fetchReactions(event)) {
    if (reaction.redacted || reaction.senderId != myUserId) continue;
    return reaction;
  }
  return null;
}
