enum CallStatus { calling, connecting, waiting, encrypting, talking }

CallStatus callStatus({
  required bool calling,
  required bool connecting,
  required bool someoneHere,
  required bool keysPending,
}) {
  if (!someoneHere) {
    if (calling) return CallStatus.calling;
    return connecting ? CallStatus.connecting : CallStatus.waiting;
  }
  return keysPending ? CallStatus.encrypting : CallStatus.talking;
}
