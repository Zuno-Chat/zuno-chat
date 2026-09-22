import 'package:matrix/matrix.dart';

const galleryGroupKey = 'im.zuno.gallery';

class GalleryGroupRef {
  final String id;
  final int index;
  final int count;

  const GalleryGroupRef({
    required this.id,
    required this.index,
    required this.count,
  });
}

Map<String, dynamic> galleryGroupContent({
  required String id,
  required int index,
  required int count,
}) => {
  galleryGroupKey: {'id': id, 'index': index, 'count': count},
};

GalleryGroupRef? galleryGroupOf(Event event) {
  final raw = event.content[galleryGroupKey];
  if (raw is! Map) return null;
  final id = raw['id'];
  final index = raw['index'];
  final count = raw['count'];
  if (id is! String || id.isEmpty) return null;
  if (index is! int || count is! int) return null;
  if (count < 2 || index < 0 || index >= count) return null;
  return GalleryGroupRef(id: id, index: index, count: count);
}

bool isGalleryMedia(Event event) =>
    !event.redacted &&
    (event.messageType == MessageTypes.Image ||
        event.messageType == MessageTypes.Video);

class GalleryGrouping {
  final List<Event> messages;
  final Map<String, List<Event>> galleries;

  const GalleryGrouping({required this.messages, required this.galleries});
}

GalleryGrouping groupGalleries(
  List<Event> messages, {
  Set<String> forceGroupIds = const {},
}) {
  final members = <String, List<Event>>{};
  for (final event in messages) {
    if (!isGalleryMedia(event)) continue;
    final ref = galleryGroupOf(event);
    if (ref == null) continue;
    members.putIfAbsent(ref.id, () => []).add(event);
  }
  members.removeWhere(
    (id, group) => group.length < 2 && !forceGroupIds.contains(id),
  );
  if (members.isEmpty) {
    return GalleryGrouping(messages: messages, galleries: const {});
  }

  final galleries = <String, List<Event>>{};
  final absorbed = <String>{};
  for (final group in members.values) {
    final anchor = group.first;
    galleries[anchor.eventId] = [...group]
      ..sort(
        (a, b) => galleryGroupOf(a)!.index.compareTo(galleryGroupOf(b)!.index),
      );
    for (final event in group) {
      if (event.eventId != anchor.eventId) absorbed.add(event.eventId);
    }
  }
  return GalleryGrouping(
    messages: messages.where((e) => !absorbed.contains(e.eventId)).toList(),
    galleries: galleries,
  );
}

class GalleryTileLayout {
  final int visible;
  final int overflow;

  const GalleryTileLayout({required this.visible, required this.overflow});
}

GalleryTileLayout galleryTileLayout(int itemCount) {
  const maxVisible = 4;
  if (itemCount <= maxVisible) {
    return GalleryTileLayout(visible: itemCount, overflow: 0);
  }
  return GalleryTileLayout(
    visible: maxVisible,
    overflow: itemCount - maxVisible,
  );
}
