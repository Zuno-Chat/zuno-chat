import 'package:matrix/matrix.dart';

final _plainName = RegExp(r'^\w+$');
const _nameSeparators = {'[', ']', ':'};

Set<String> mentionFragmentsOf(Event event) {
  final mentions = event.content['m.mentions'];
  if (mentions is! Map) return const {};
  final ids = mentions['user_ids'];
  if (ids is! List) return const {};

  final fragments = <String>{};
  for (final id in ids.whereType<String>()) {
    final localpart = id.localpart;
    if (localpart != null) fragments.add('@${localpart.toLowerCase()}');

    final name = event.room
        .getState(EventTypes.RoomMember, id)
        ?.content['displayname'];
    if (name is! String || name.isEmpty || _nameSeparators.any(name.contains)) {
      continue;
    }
    fragments.add(
      (_plainName.hasMatch(name) ? '@$name' : '@[$name]').toLowerCase(),
    );
  }
  return fragments;
}
