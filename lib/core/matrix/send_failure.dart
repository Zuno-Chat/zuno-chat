import 'package:matrix/matrix.dart';

import '../errors/best_effort.dart';

bool isDiscardablePlaceholder(Event? event) =>
    event != null && !event.status.isSent;

Future<void> discardSendPlaceholder(Room room, String txid) async {
  final Event? event;
  try {
    event = await room.getEventById(txid);
  } catch (_) {
    return;
  }
  if (!isDiscardablePlaceholder(event)) return;
  await runBestEffort(
    () => event!.cancelSend(),
    label: 'discard send placeholder $txid',
  );
}

const _bytesPerMegabyte = 1000000;

String tooLargeToSendMessage(FileTooBigMatrixException error) {
  final limitMb = (error.maxFileSize / _bytesPerMegabyte).round();
  return 'Too large to send. The limit is $limitMb MB.';
}
