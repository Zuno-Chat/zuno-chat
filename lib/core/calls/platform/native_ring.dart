enum NativeRingSource { sync, push, generic, bfu }

class NativeRing {
  const NativeRing({
    required this.uuid,
    required this.roomId,
    required this.callId,
    required this.callerId,
    required this.video,
    required this.source,
  });

  final String uuid;
  final String? roomId;
  final String? callId;
  final String callerId;
  final bool video;
  final NativeRingSource source;

  bool get bound => roomId != null && callId != null;

  static NativeRing? tryParse(Object? arguments) {
    if (arguments is! Map) return null;
    final uuid = arguments['uuid'];
    final source = NativeRingSource.values.asNameMap()[arguments['source']];
    if (uuid is! String || uuid.isEmpty || source == null) return null;
    final roomId = arguments['roomId'];
    final callId = arguments['callId'];
    final callerId = arguments['callerId'];
    return NativeRing(
      uuid: uuid,
      roomId: roomId is String && roomId.isNotEmpty ? roomId : null,
      callId: callId is String && callId.isNotEmpty ? callId : null,
      callerId: callerId is String ? callerId : '',
      video: arguments['video'] == true,
      source: source,
    );
  }
}
