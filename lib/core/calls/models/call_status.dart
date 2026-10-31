enum CallStatus { calling, connecting, waiting, encrypting, talking, ended }

CallStatus callStatus({
  required bool ending,
  required bool calling,
  required bool connecting,
  required bool someoneHere,
  required bool keysPending,
}) {
  if (ending) return CallStatus.ended;
  if (!someoneHere) {
    if (calling) return CallStatus.calling;
    return connecting ? CallStatus.connecting : CallStatus.waiting;
  }
  return keysPending ? CallStatus.encrypting : CallStatus.talking;
}
