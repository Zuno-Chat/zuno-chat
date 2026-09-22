class VoipParticipantId {
  final String userId;
  final String deviceId;

  const VoipParticipantId({required this.userId, required this.deviceId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoipParticipantId &&
          userId == other.userId &&
          deviceId == other.deviceId;

  @override
  int get hashCode => Object.hash(userId, deviceId);

  @override
  String toString() => 'VoipParticipantId($userId/$deviceId)';
}
