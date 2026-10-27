import 'package:matrix/matrix.dart';

bool sendsEncrypted(Room room) =>
    room.encrypted && room.client.encryptionEnabled;
