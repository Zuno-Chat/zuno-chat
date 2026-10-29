import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart';

import '../ui/visible_in_front.dart';

bool syncTouchesRoom(SyncUpdate update, String roomId) {
  final rooms = update.rooms;
  if (rooms == null) return false;
  return (rooms.join?.containsKey(roomId) ?? false) ||
      (rooms.invite?.containsKey(roomId) ?? false) ||
      (rooms.leave?.containsKey(roomId) ?? false);
}

bool syncChangesRoomState(SyncUpdate update, String roomId) {
  if (update.accountData?.any((e) => e.type == 'm.direct') ?? false) {
    return true;
  }
  final rooms = update.rooms;
  if (rooms == null) return false;
  if ((rooms.invite?.containsKey(roomId) ?? false) ||
      (rooms.leave?.containsKey(roomId) ?? false)) {
    return true;
  }
  final joined = rooms.join?[roomId];
  if (joined == null) return false;
  return (joined.summary?.toJson().isNotEmpty ?? false) ||
      (joined.state?.isNotEmpty ?? false) ||
      (joined.timeline?.events?.any((e) => e.stateKey != null) ?? false);
}

bool syncCarriesEphemeral(SyncUpdate update, String roomId, String type) =>
    update.rooms?.join?[roomId]?.ephemeral?.any((e) => e.type == type) ?? false;

typedef SyncFilter = bool Function(SyncUpdate update);
typedef RoomStateFilter = bool Function(
  String roomId,
  StrippedStateEvent state,
);

class RoomChanges {
  final Client client;
  final SyncFilter? syncs;
  final RoomStateFilter? states;
  final Object _identity;

  RoomChanges.where(this.client, {this.syncs, this.states})
    : _identity = (client, syncs, states);

  RoomChanges.state(Room room)
    : client = room.client,
      syncs = ((update) => syncChangesRoomState(update, room.id)),
      states = ((roomId, _) => roomId == room.id),
      _identity = (#state, room);

  RoomChanges.any(Room room)
    : client = room.client,
      syncs = ((update) => syncTouchesRoom(update, room.id)),
      states = ((roomId, _) => roomId == room.id),
      _identity = (#any, room);

  RoomChanges.ephemeral(Room room, String type)
    : client = room.client,
      syncs = ((update) => syncCarriesEphemeral(update, room.id, type)),
      states = null,
      _identity = (#ephemeral, room, type);

  RoomChanges.everywhere(this.client)
    : syncs = ((_) => true),
      states = ((_, _) => true),
      _identity = (#everywhere, client);

  Stream<void> get stream {
    StreamSubscription<SyncUpdate>? syncSub;
    StreamSubscription<({String roomId, StrippedStateEvent state})>? stateSub;
    var pending = false;
    late final StreamController<void> controller;

    void changed() {
      if (pending) return;
      pending = true;
      scheduleMicrotask(() {
        pending = false;
        if (!controller.isClosed) controller.add(null);
      });
    }

    controller = StreamController<void>(
      sync: true,
      onListen: () {
        final syncs = this.syncs;
        final states = this.states;
        if (syncs != null) {
          syncSub = client.onSync.stream.listen((update) {
            if (syncs(update)) changed();
          });
        }
        if (states != null) {
          stateSub = client.onRoomState.stream.listen((update) {
            if (states(update.roomId, update.state)) changed();
          });
        }
      },
      onCancel: () async {
        await syncSub?.cancel();
        await stateSub?.cancel();
        await controller.close();
      },
    );
    return controller.stream;
  }

  @override
  bool operator ==(Object other) =>
      other is RoomChanges && other._identity == _identity;

  @override
  int get hashCode => _identity.hashCode;
}

class RoomChangesBuilder extends StatefulWidget {
  final RoomChanges changes;
  final WidgetBuilder builder;
  final VoidCallback? onChange;

  const RoomChangesBuilder({
    super.key,
    required this.changes,
    required this.builder,
    this.onChange,
  });

  @override
  State<RoomChangesBuilder> createState() => _RoomChangesBuilderState();
}

class _RoomChangesBuilderState extends State<RoomChangesBuilder>
    with VisibleInFront<RoomChangesBuilder> {
  StreamSubscription<void>? _sub;
  bool _missed = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _sub = widget.changes.stream.listen((_) => _changed());
  }

  @override
  void didUpdateWidget(RoomChangesBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.changes == widget.changes) return;
    unawaited(_sub?.cancel());
    _listen();
  }

  void _changed() {
    if (!mounted) return;
    if (!visibleInFront) {
      _missed = true;
      return;
    }
    _missed = false;
    widget.onChange?.call();
    if (mounted) setState(() {});
  }

  @override
  void onVisibleInFrontChanged() {
    if (!_missed || !visibleInFront) return;
    scheduleMicrotask(() {
      if (_missed) _changed();
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
