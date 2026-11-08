import 'package:clock/clock.dart';
import 'package:matrix/matrix.dart';

typedef SavedServerAnswer = ({Map<String, Object?> content, DateTime savedAt});

Future<SavedServerAnswer?> readSavedServerAnswer(
  Client client,
  String key,
) async {
  final saved = await client.database.getCustomCacheObject(key);
  final content = saved?.content;
  if (content == null) return null;
  if (content['user_id'] != client.userID) return null;
  final ms = content['saved_at'];
  if (ms is! int) return null;
  return (
    content: {...content}
      ..remove('user_id')
      ..remove('saved_at'),
    savedAt: DateTime.fromMillisecondsSinceEpoch(ms),
  );
}

Future<void> saveServerAnswer(
  Client client,
  String key,
  Map<String, Object?> content,
) => client.database.cacheCustomObject(key, {
  ...content,
  'user_id': client.userID,
  'saved_at': clock.now().millisecondsSinceEpoch,
});

bool isFresh(DateTime savedAt, Duration lifetime) {
  final age = clock.now().difference(savedAt);
  return !age.isNegative && age < lifetime;
}
