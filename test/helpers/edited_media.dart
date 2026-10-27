import 'package:matrix/matrix.dart';

import 'fake_matrix.dart';

List<Event> editedPhoto(
  Room room, {
  Map<String, Object?> originalExtra = const {},
}) {
  final media = {
    'msgtype': MessageTypes.Image,
    'filename': 'p1.jpg',
    'url': 'mxc://example.org/p1',
    'info': {'w': 400, 'h': 300, 'mimetype': 'image/jpeg'},
  };
  return [
    buildTestEvent(
      room,
      eventId: r'$e1',
      senderId: '@bob:example.org',
      originServerTs: DateTime(2026, 9, 20, 12, 1),
      status: EventStatus.synced,
      content: {
        ...media,
        'body': '* New caption',
        'm.new_content': {...media, 'body': 'New caption'},
        'm.relates_to': {
          'rel_type': RelationshipTypes.edit,
          'event_id': r'$p1',
        },
      },
    ),
    buildTestEvent(
      room,
      eventId: r'$p1',
      senderId: '@bob:example.org',
      originServerTs: DateTime(2026, 9, 20, 12),
      status: EventStatus.synced,
      content: {...media, 'body': 'Old caption', ...originalExtra},
    ),
  ];
}
