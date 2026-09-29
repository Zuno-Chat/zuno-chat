import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../errors/best_effort.dart';
import '../settings/app_preferences_provider.dart';
import 'matrix_client_provider.dart';
import 'optimistic_room_state.dart';

final joinRequestsProvider =
    NotifierProvider<JoinRequestsNotifier, Set<String>>(
      JoinRequestsNotifier.new,
    );

String _askedKey(Client client) => 'communities.asked.${client.userID}';

class JoinRequestsNotifier extends Notifier<Set<String>> {
  late Client _client;
  late SharedPreferences _prefs;
  late String _key;
  final _joining = <String>{};

  @override
  Set<String> build() {
    _client = ref.watch(matrixClientProvider);
    _prefs = ref.watch(sharedPreferencesProvider);
    _key = _askedKey(_client);
    final sub = _client.onSync.stream.listen(_settle);
    final accounts = _client.onLoginStateChanged.stream.listen((_) {
      if (_key != _askedKey(_client)) ref.invalidateSelf();
    });
    ref.onDispose(() {
      sub.cancel();
      accounts.cancel();
    });
    scheduleMicrotask(() => _settle(null));
    return {...?_prefs.getStringList(_key)};
  }

  Future<void> ask(String roomId, {List<String>? via}) async {
    await _client.knockRoom(roomId, via: via);
    _save({...state, roomId});
  }

  Future<void> withdraw(String roomId) async {
    await _client.leaveRoom(roomId);
    _save({...state}..remove(roomId));
  }

  void _settle(SyncUpdate? update) {
    if (!ref.mounted || state.isEmpty) return;
    final left = update?.rooms?.leave?.keys.toSet() ?? const <String>{};
    final keep = {...state};
    for (final id in state) {
      final room = _client.getRoomById(id);
      if (left.contains(id) || room?.membership == Membership.join) {
        keep.remove(id);
      } else if (room != null && room.membership == Membership.invite) {
        unawaited(_join(room));
      }
    }
    if (keep.length != state.length) _save(keep);
  }

  Future<void> _join(Room room) async {
    if (!_joining.add(room.id)) return;
    await runBestEffort(room.join, label: 'join approved');
    _joining.remove(room.id);
    if (ref.mounted) _save({...state}..remove(room.id));
  }

  void _save(Set<String> ids) {
    state = ids;
    unawaited(_prefs.setStringList(_key, ids.toList()));
  }
}

List<User> pendingJoinRequests(Room room) => room
    .getParticipants(const [Membership.knock])
    .where((user) => user.id != room.client.userID)
    .toList();

bool canAnswerJoinRequests(Room room) =>
    room.membership == Membership.join && room.canInvite && room.canKick;

Future<void> letIn(Room room, String userId) async {
  await room.invite(userId);
  _showMembership(room, userId, Membership.invite);
}

Future<void> declineJoinRequest(Room room, String userId) async {
  await room.kick(userId);
  _showMembership(room, userId, Membership.leave);
}

void _showMembership(Room room, String userId, Membership membership) =>
    applyOptimisticRoomState(room, EventTypes.RoomMember, {
      ...?room.getState(EventTypes.RoomMember, userId)?.content,
      'membership': membership.name,
    }, stateKey: userId);
