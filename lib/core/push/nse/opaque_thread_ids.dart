import 'nse_channel.dart';

const roomTokenPrefix = 't:';

class OpaqueThreadIds {
  OpaqueThreadIds({Future<String?> Function(String roomId)? threadKey})
    : _threadKey = threadKey ?? const NseChannel().threadKey;

  static final instance = OpaqueThreadIds();

  final Future<String?> Function(String roomId) _threadKey;
  final _tokens = <String, String>{};

  Future<String?> tokenFor(String roomId) async {
    final known = _tokens[roomId];
    if (known != null) return known;
    final token = await _threadKey(roomId);
    if (token != null) _tokens[roomId] = token;
    return token;
  }

  Future<List<String>> tokensFor(Iterable<String> roomIds) async => [
    for (final roomId in roomIds) ?await tokenFor(roomId),
  ];

  Future<String?> roomFor(String token, Iterable<String> roomIds) async {
    for (final MapEntry(:key, :value) in _tokens.entries) {
      if (value == token) return key;
    }
    for (final roomId in roomIds.toList()) {
      if (await tokenFor(roomId) == token) return roomId;
    }
    return null;
  }

  void reset() => _tokens.clear();
}

Future<String?> roomIdToOpen(
  String target,
  Iterable<String> roomIds, {
  required bool opaque,
  OpaqueThreadIds? threadIds,
}) async {
  if (!opaque || !target.startsWith(roomTokenPrefix)) return target;
  return (threadIds ?? OpaqueThreadIds.instance).roomFor(
    target.substring(roomTokenPrefix.length),
    roomIds,
  );
}
