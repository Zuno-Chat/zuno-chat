import 'package:matrix/matrix.dart';

bool isAttachmentMessageType(String messageType) => const {
  MessageTypes.Image,
  MessageTypes.Sticker,
  MessageTypes.Video,
  MessageTypes.Audio,
  MessageTypes.File,
}.contains(messageType);
